import SwiftUI

/// Редактор карточки (S2): шторка Half / Full. Тап по тексту — Full. Шапка: точка
/// тега (поповер: цвета + Spoiler / Lock) и «…» (Copy / Share / Delete). «Aa» —
/// панель Markdown над клавиатурой. Пустая карточка при закрытии удаляется (Р10).
/// shortcut: разметка в тексте видна целиком; прятать её вне строки под курсором,
/// как на Mac, — после MVP.
struct EditorSheet: View {
    @Bindable var board: BoardModel
    @Bindable var card: Card
    @State var detent: PresentationDetent
    let lock: LockSession

    @State private var selection: TextSelection?
    @State private var showTags = false
    @State private var showMarkdown = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TextEditor(text: $card.text, selection: $selection)
            .font(.system(size: 17))
            .foregroundStyle(Theme.text)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all) // текст гаснет с размытием под шапкой
            .scrollDismissesKeyboard(.interactively)
            .focused($focused)
            .padding(.horizontal, 16)
            .safeAreaBar(edge: .top) { header }
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { keyboardBar }
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    wrap("bold", "**"); wrap("italic", "*"); wrap("strikethrough", "~~"); wrap("highlighter", "==")
                    prefix("textformat.size", "# "); prefix("list.bullet", "- "); prefix("checklist", "- [ ] "); prefix("text.quote", "> ")
                    wrap("chevron.left.forwardslash.chevron.right", "`")
                    Button { insertLink() } label: { Image(systemName: "link") }
                }
            }
            Button { showMarkdown = false } label: { Image(systemName: "xmark") }
        } else {
            Spacer()
            Button { showMarkdown = true } label: { Text("Aa").font(.system(size: 17, weight: .semibold)) }
        }
    }

    private var selectedRange: NSRange {
        let text = card.text
        if case .selection(let range) = selection?.indices { return NSRange(range, in: text) }
        return NSRange(location: (text as NSString).length, length: 0)
    }

    private func apply(range: NSRange, replacement: String, selectionAfter: NSRange) {
        let ns = card.text as NSString
        card.text = ns.replacingCharacters(in: range, with: replacement)
        if let r = Range(selectionAfter, in: card.text) { selection = TextSelection(range: r) }
    }

    private func wrap(_ symbol: String, _ marker: String) -> some View {
        Button {
            let edit = MarkdownFormatting.toggle(marker, in: card.text as NSString, selection: selectedRange)
            apply(range: edit.range, replacement: edit.replacement, selectionAfter: edit.selection)
        } label: { Image(systemName: symbol) }
    }

    /// Блочная разметка — в начало текущей строки (повтор — снимает).
    private func prefix(_ symbol: String, _ marker: String) -> some View {
        Button {
            let ns = card.text as NSString
            let sel = selectedRange
            let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let m = (marker as NSString).length
            if line.length >= m, ns.substring(with: NSRange(location: line.location, length: m)) == marker {
                apply(range: NSRange(location: line.location, length: m), replacement: "",
                      selectionAfter: NSRange(location: max(line.location, sel.location - m), length: sel.length))
            } else {
                apply(range: NSRange(location: line.location, length: 0), replacement: marker,
                      selectionAfter: NSRange(location: sel.location + m, length: sel.length))
            }
        } label: { Image(systemName: symbol) }
    }

    private func insertLink() {
        let sel = selectedRange
        let selected = (card.text as NSString).substring(with: sel)
        let replacement = "[\(selected)](https://)"
        apply(range: sel, replacement: replacement,
              selectionAfter: NSRange(location: sel.location + (selected as NSString).length + 3, length: 8))
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
