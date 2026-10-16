import SwiftUI

/// Редактор карточки (S2): шторка Half / Full. Тап по тексту — Full. Шапка: точка
/// тега (поповер: цвета + Spoiler / Lock) и «…» (Copy / Share / Delete). Markdown
/// живой — служебных символов не видно (MarkdownTextView). «Aa» при правке —
/// панель Markdown над клавиатурой. Пустая карточка при закрытии удаляется (Р10).
struct EditorSheet: View {
    @Bindable var board: BoardModel
    @Bindable var card: Card
    @State var detent: PresentationDetent

    @State private var editor = MarkdownEditorController()
    @State private var showTags = false
    @State private var showMarkdown = false
    @State private var focused = false
    @State private var showLink = false
    @State private var linkTitle = ""
    @State private var linkURL = ""
    @State private var linkNeedsTitle = false
    @Namespace private var glass
    @State private var viewport: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Прокрутка — своя, SwiftUI: под шапкой (safeAreaBar) текст гаснет системным
        // размытием края; редактор внутри растёт по тексту.
        ScrollView {
            MarkdownTextView(text: $card.text, isFocused: $focused, controller: editor, minHeight: viewport)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollDismissesKeyboard(.interactively)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
        .safeAreaBar(edge: .top) { EditorHeader(card: card, onDelete: delete) }
            .overlay(alignment: .topLeading) {
                // Поповер тега «вытекает» из кнопки (морфинг стекла); тап мимо — закрыть.
                ZStack(alignment: .topLeading) {
                    if showTags {
                        Color.black.opacity(0.001).ignoresSafeArea()
                            .onTapGesture { withAnimation(.bouncy) { showTags = false } }
                    }
                    TagControl(card: card, board: board, expanded: $showTags)
                }
            }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(showTags ? .hidden : .visible) // подложка тега встаёт на его место
        // «Aa» — всегда при правке; своя плашка над клавиатурой с отступом, а не
        // toolbar клавиатуры, прижатый к ней вплотную.
        .overlay(alignment: .bottom) {
            if focused {
                keyboardBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
            }
        }
        .alert("Add Link", isPresented: $showLink) {
            if linkNeedsTitle { TextField("Text", text: $linkTitle) }
            TextField("https://", text: $linkURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Add") { editor.insertLink(title: linkTitle, url: linkURL) }
                .disabled(linkURL.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onChange(of: focused) { _, isFocused in if isFocused { withAnimation { detent = .large } } }
        .onChange(of: card.text) { board.scheduleDebouncedSave() }
        .onAppear { board.editingCardID = card.id }
        .onDisappear(perform: close)
        .preferredColorScheme(.dark)
    }

    // MARK: - Клавиатура: «Aa» → панель Markdown

    /// «Aa» и панель — одно стекло: кнопка «вытекает» в панель и стекается обратно.
    /// Как TagControl: в GlassEffectContainer — только пустые стеклянные формы с
    /// glassEffectID, значки — поверх, вне контейнера (стекло прямо на ряду кнопок
    /// не морфилось: состояние менялось за один кадр). Без выделения панель по
    /// размеру своих значков и прижата вправо, к месту «Aa»; с выделением — во всю ширину.
    private var keyboardBar: some View {
        let width: CGFloat? = editor.hasSelection ? nil : Self.starterWidth
        return ZStack(alignment: .trailing) {
            GlassEffectContainer(spacing: 8) {
                if showMarkdown {
                    Color.clear
                        .frame(maxWidth: width ?? .infinity)
                        .frame(height: 52)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectID("markdown", in: glass)
                } else {
                    Button { withAnimation(.bouncy) { showMarkdown = true } } label: {
                        Color.clear.frame(width: 52, height: 52).contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("markdown", in: glass)
                }
            }
            if showMarkdown {
                HStack(spacing: 0) {
                    if editor.hasSelection {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) { selectionTools }.padding(.leading, 12)
                        }
                        .scrollEdgeEffectStyle(.soft, for: .horizontal)
                    } else {
                        HStack(spacing: 0) { starterTools }.padding(.leading, 12) // padding на группе раздал бы отступ каждому значку
                    }
                    Button { withAnimation(.bouncy) { showMarkdown = false } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 7)
                }
                .frame(maxWidth: width ?? .infinity)
                .frame(height: 52)
                .clipShape(.capsule)
                // Значки уходят раньше, чем стекло стечётся в каплю; появляются, когда оно разлилось.
                .transition(.asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.18).delay(0.08)),
                                        removal: .opacity.animation(.easeOut(duration: 0.08))))
            } else {
                Text("Aa").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 52, height: 52)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.bouncy, value: editor.hasSelection)
    }

    /// 4 значка по 44 + ✕ 44 + поля по краям капсулы.
    private static let starterWidth: CGFloat = 4 * 44 + 44 + 12 + 7

    /// Без выделения — только то, с чего начинают строку.
    @ViewBuilder
    private var starterTools: some View {
        tool("textformat.size", block: "# ") { editor.block("# ") }
        tool("list.bullet", block: "- ") { editor.block("- ") }
        tool("list.number", block: "1. ") { editor.block("1. ") }
        tool("checklist", block: "- [ ] ") { editor.block("- [ ] ") }
    }

    /// С выделением — всё: оформление строки и блока.
    @ViewBuilder
    private var selectionTools: some View {
        // Строка
        tool("bold", active: "**") { editor.wrap("**") }
        tool("italic", active: "*") { editor.wrap("*") }
        tool("underline", active: "~") { editor.wrap("~") }
        tool("strikethrough", active: "~~") { editor.wrap("~~") }
        tool("highlighter", active: "==") { editor.wrap("==") }
        tool("chevron.left.forwardslash.chevron.right", active: "`") { editor.wrap("`") }
        tool("link", active: "link") { askLink() }
        Divider().frame(height: 24).padding(.horizontal, 6)
        // Блок
        starterTools
        tool("text.quote", block: "> ") { editor.block("> ") }
        tool("curlybraces", block: "```") { editor.codeBlock() }
    }

    /// Кнопка панели: один набор значков, один размер и вес; активный стиль — акцентом.
    private func tool(_ symbol: String, active inline: String? = nil, block: String? = nil, action: @escaping () -> Void) -> some View {
        let isOn = inline.map { editor.activeInlines.contains($0) } ?? (block == editor.activeBlock && block != nil)
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isOn ? Theme.accent : Theme.text)
                .frame(width: 44, height: 44)
                .background { if isOn { Circle().fill(Theme.accent.opacity(0.18)).frame(width: 36, height: 36) } }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func askLink() {
        linkTitle = ""
        linkURL = ""
        linkNeedsTitle = editor.selectedText().isEmpty
        showLink = true
    }

    // MARK: - Закрытие

    private func delete() {
        board.editingCardID = nil
        board.deleteCard(id: card.id)
        dismiss()
    }

    private func close() {
        board.flushPendingSave()
        board.editingCardID = nil
        if card.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, board.cardsByWorkspace.values.contains(where: { $0.contains { $0.id == card.id } }) {
            board.deleteCard(id: card.id)
        }
    }
}

/// Шапка редактора: место кнопки тега (она в оверлее) и «…» (Copy / Share / Delete).
private struct EditorHeader: View {
    @Bindable var card: Card
    var onDelete: () -> Void

    var body: some View {
        HStack {
            Color.clear.frame(width: 24, height: 44)
            Spacer()
            Menu {
                CardActions(card: card, onDelete: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect) // без стеклянного фона (доводка 3)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
    }
}

/// Кнопка тега в шапке редактора: стеклянная точка цвета тега 24 pt (без тега —
/// полупрозрачная). По тапу она «перетекает» в одну стеклянную подложку во всю
/// ширину шторки (как в Figma): ✕ на месте кнопки, плоские точки цветов того же
/// размера, «снять тег» в конце; под подложкой — Spoiler / Lock.
private struct TagControl: View {
    @Bindable var card: Card
    let board: BoardModel
    @Binding var expanded: Bool
    @Namespace private var glass

    private static let dot: CGFloat = 24
    /// Центр кнопки — 32 pt от верха и от края; подложка вокруг неё с равными полями.
    private static let inset: CGFloat = 20
    private static let panelPadding: CGFloat = 12

    var body: some View {
        ZStack(alignment: .topLeading) {
        GlassEffectContainer(spacing: 10) {
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Стекло — пустая капсула, ряд — поверх контейнера (оверлей ниже): контейнер
                    // рисует стекло над всем, что в нём, и цвета точек мутнеют.
                    Color.clear
                        .frame(height: Self.dot + Self.panelPadding * 2)
                        .frame(maxWidth: .infinity)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectID("tag", in: glass)

                    HStack(spacing: 8) {
                        privacyButton(.spoiler, title: "Spoiler", symbol: "sparkles")
                        privacyButton(.lock, title: "Lock", symbol: "lock.fill")
                    }
                }
                .padding(Self.inset - Self.panelPadding)
            } else {
                Button { withAnimation(.bouncy) { expanded = true } } label: {
                    // Прозрачная «начинка» сама тапы не ловит — нужна форма касания;
                    // она шире круга, чтобы в 24 pt было легко попасть.
                    Color.clear.frame(width: Self.dot, height: Self.dot).padding(10).contentShape(.circle).padding(-10)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(card.tagColor?.color ?? .white.opacity(0.15)).interactive(), in: .circle)
                .glassEffectID("tag", in: glass)
                .padding(Self.inset)
            }
        }
        if expanded { row.padding(Self.inset - Self.panelPadding).transition(.opacity) }
        }
    }

    private var row: some View {
        HStack(spacing: 0) {
            iconButton("xmark", size: 15) { withAnimation(.bouncy) { expanded = false } } // только закрыть
            ForEach(CardTagColor.allCases) { tag in
                Spacer(minLength: 4)
                colorButton(tag)
            }
            Spacer(minLength: 4)
            iconButton("minus.circle.fill") { select(nil) } // снять тег
        }
        .padding(Self.panelPadding)
        .frame(maxWidth: .infinity)
    }

    private func select(_ tag: CardTagColor?) {
        card.tagColor = tag
        board.saveImmediately()
        withAnimation(.bouncy) { expanded = false }
    }

    private func iconButton(_ symbol: String, size: CGFloat = 20, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: Self.dot, height: Self.dot)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }

    /// Цвет — стеклянная капля с оттенком тега; выбранный — белая точка в центре.
    private func colorButton(_ tag: CardTagColor) -> some View {
        Button { select(tag) } label: {
            ZStack { if card.tagColor == tag { Circle().fill(.white).frame(width: 8, height: 8) } }
                .frame(width: Self.dot, height: Self.dot)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(tag.color).interactive(), in: .circle)
    }

    private func privacyButton(_ mode: CardPrivacyMode, title: String, symbol: String) -> some View {
        let isOn = card.privacyMode == mode
        return Button {
            card.privacyMode = isOn ? .none : mode
            board.saveImmediately()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 16))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.text)
            .frame(width: 76, height: 52)
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(Theme.accent.opacity(0.5)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 18))
        .glassEffectID(mode.rawValue, in: glass)
    }
}
