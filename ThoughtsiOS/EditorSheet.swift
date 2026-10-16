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
        VStack(alignment: .leading, spacing: 0) {
            header
            TextEditor(text: $card.text, selection: $selection)
                .font(.system(size: 17))
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(.horizontal, 16)
        }
        .padding(.top, 20)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
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
            Button { showTags = true } label: {
                Circle()
                    .fill(card.tagColor?.color ?? Color.white.opacity(0.3))
                    .frame(width: 22, height: 22)
                    .frame(width: 44, height: 44)
            }
            .popover(isPresented: $showTags) { tagPopover.presentationCompactAdaptation(.popover) }
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
            }
        }
        .padding(.horizontal, 12)
    }

    /// Поповер тега — как поповер точки на Mac: цвета, под ними Spoiler и Lock.
    private var tagPopover: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                tagButton(nil)
                ForEach(CardTagColor.allCases) { tagButton($0) }
            }
            HStack(spacing: 8) {
                privacyButton(.spoiler, title: "Spoiler", symbol: "sparkles")
                privacyButton(.lock, title: "Lock", symbol: "lock.fill")
            }
        }
        .padding(14)
    }

    private func tagButton(_ tag: CardTagColor?) -> some View {
        Button {
            card.tagColor = tag
            board.saveImmediately()
        } label: {
            ZStack {
                if let tag {
                    Circle().fill(tag.color).frame(width: 26, height: 26)
                    if card.tagColor == tag { Circle().fill(.white).frame(width: 8, height: 8) } // выбранный
                } else {
                    Image(systemName: "xmark.circle").font(.system(size: 24)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func privacyButton(_ mode: CardPrivacyMode, title: String, symbol: String) -> some View {
        let isOn = card.privacyMode == mode
        return Button {
            card.privacyMode = isOn ? .none : mode
            board.saveImmediately()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 17))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.text)
            .frame(width: 72, height: 52)
            .background(isOn ? Color.white.opacity(0.15) : .clear, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
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
