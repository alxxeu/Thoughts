import SwiftUI

/// Редактор карточки (S2): шторка Half / Full. Тап по тексту — Full. Шапка: точка
/// тега (поповер: цвета + Spoiler / Lock) и «…» (Copy / Share / Delete). Markdown
/// живой — служебных символов не видно (MarkdownTextView). «Aa» при выделении —
/// панель Markdown над клавиатурой. Пустая карточка при закрытии удаляется (Р10).
struct EditorSheet: View {
    @Bindable var board: BoardModel
    @Bindable var card: Card
    @State var detent: PresentationDetent
    let lock: LockSession

    @State private var editor = MarkdownEditorController()
    @State private var showTags = false
    @State private var showMarkdown = false
    @State private var focused = false
    @State private var showLink = false
    @State private var linkTitle = ""
    @State private var linkURL = ""
    @State private var linkNeedsTitle = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MarkdownTextView(text: $card.text, isFocused: $focused, controller: editor)
            .ignoresSafeArea(.container, edges: .bottom)
            // Шапка — поверх текста: он уходит под неё и гаснет с размытием (своё
            // затухание: системное у safeAreaBar не работает над UIKit-редактором).
            .overlay(alignment: .top) {
                header.background(alignment: .top) {
                    Rectangle().fill(.ultraThinMaterial)
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55),
                                                     .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                        .frame(height: 84)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
            }
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
        .animation(.snappy, value: editor.hasSelection)
        .animation(.snappy, value: showMarkdown)
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

    // MARK: - Шапка

    private var header: some View {
        HStack {
            Color.clear.frame(width: 24, height: 44) // место кнопки тега (она в оверлее)
            Spacer()
            Menu {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = card.text }
                ShareLink(item: card.text) { Label("Share", systemImage: "square.and.arrow.up") }
                Button("Delete", systemImage: "trash", role: .destructive) { delete() }
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

    // MARK: - Клавиатура: «Aa» → панель Markdown

    @ViewBuilder
    private var keyboardBar: some View {
        if showMarkdown {
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        if editor.hasSelection { selectionTools } else { starterTools }
                    }
                    .padding(.horizontal, 8)
                    .animation(.snappy, value: editor.hasSelection)
                }
                .scrollEdgeEffectStyle(.soft, for: .horizontal)
                Button { showMarkdown = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 44, height: 44)
                }
                .padding(.trailing, 4)
            }
            .frame(height: 52)
            .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            HStack {
                Spacer()
                Button { showMarkdown = true } label: {
                    Text("Aa").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }
        }
    }

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
        tool("textformat.size", block: "# ") { editor.block("# ") }
        tool("list.bullet", block: "- ") { editor.block("- ") }
        tool("list.number", block: "1. ") { editor.block("1. ") }
        tool("checklist", block: "- [ ] ") { editor.block("- [ ] ") }
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
