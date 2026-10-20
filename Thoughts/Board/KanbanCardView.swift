import SwiftUI

/// Карточка-виджет «канбан»: колонки, в них плитки-пункты со своим текстом,
/// кнопками ×/≡ и «+» (см. KanbanBoard). Заменяет текстовый редактор, пока
/// текст карточки начинается с метки `::: board`. Источник истины — текст
/// карточки: каждая правка сразу пишется в него, внешние изменения (синк,
/// Ask AI, ⌘Z) перерисовывают виджет.
struct KanbanCardView: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    var cardSize: CGSize
    var typography: CardTypography
    var onTextChange: () -> Void
    var onFocusChange: (Bool) -> Void = { _ in }
    var onEditAsText: () -> Void

    @State private var board: KanbanBoard
    @FocusState private var focus: FocusTarget?
    @State private var undoHost = UndoHost()
    @Environment(\.undoManager) private var undoManager

    fileprivate enum FocusTarget: Hashable {
        case title(KanbanBoard.Column.ID)
        case item(KanbanBoard.Item.ID)
    }

    /// Получатель отмены: UndoManager держит цель по ссылке.
    private final class UndoHost {
        var apply: (String) -> Void = { _ in }
    }

    init(text: Binding<String>, isFocused: Binding<Bool>, cardSize: CGSize, typography: CardTypography,
         onTextChange: @escaping () -> Void, onFocusChange: @escaping (Bool) -> Void = { _ in },
         onEditAsText: @escaping () -> Void) {
        _text = text
        _isFocused = isFocused
        self.cardSize = cardSize
        self.typography = typography
        self.onTextChange = onTextChange
        self.onFocusChange = onFocusChange
        self.onEditAsText = onEditAsText
        _board = State(initialValue: KanbanBoard.parse(text.wrappedValue) ?? KanbanBoard(columns: [.init(title: "", items: [])]))
    }

    private static let sidePadding: CGFloat = 20
    /// Подсказки имён первых колонок — «намёк», что их можно переименовать.
    private static let titleHints = ["Plan", "To go", "Ready"]
    private static func titleHint(_ column: Int) -> String? {
        titleHints.indices.contains(column) ? titleHints[column] : nil
    }
    private var ink: Color { Color(nsColor: typography.color) }
    private var itemFont: Font { Font(typography.font as CTFont) }
    private var titleFont: Font {
        let size = typography.font.pointSize * 1.6
        return Font((NSFont(descriptor: typography.font.fontDescriptor, size: size) ?? typography.font) as CTFont).bold()
    }

    var body: some View {
        let columnWidth = max((cardSize.width - Self.sidePadding * 2) / CGFloat(board.columns.count), 80)
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(board.columns.enumerated()), id: \.element.id) { index, column in
                    if index > 0 {
                        Rectangle().fill(ink.opacity(0.22)).frame(width: 1)
                            .frame(maxHeight: .infinity)
                    }
                    columnView(column, index: index)
                        .frame(width: columnWidth - (index > 0 ? 0.5 : 0), alignment: .top)
                }
            }
            // Равная высота колонок: разделители тянутся на всю высоту самой высокой.
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: max(cardSize.height - 70, 60), alignment: .top)
            .padding(.horizontal, Self.sidePadding)
            .padding(.top, 38)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .contextMenu {
            Button("Add Column") { addColumn() }
            Button("Edit as Text") { onEditAsText() }
        }
        .onChange(of: text) { _, newText in
            // Текст поменяли снаружи (синк, Ask AI, импорт) — перечитать.
            guard newText != board.serialized(), let parsed = KanbanBoard.parse(newText) else { return }
            board = parsed
        }
        .onChange(of: focus) { _, newValue in
            let focused = newValue != nil
            if isFocused != focused { isFocused = focused }
            onFocusChange(focused)
        }
        .onChange(of: isFocused) { _, wants in
            // Карточке выдали фокус снаружи (новая карточка из шаблона) — в первый пункт.
            if wants, focus == nil, let first = board.columns.first {
                focus = first.items.first.map { .item($0.id) } ?? .title(first.id)
            }
        }
        .onAppear { undoHost.apply = { restore($0) } }
    }

    // MARK: - Колонка

    private func columnView(_ column: KanbanBoard.Column, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Пока имени нет — полупрозрачная подсказка (Plan / To go / Ready);
            // она становится настоящим именем, когда в колонке появляется пункт.
            TextField("", text: titleBinding(column.id),
                      prompt: Text(Self.titleHint(index) ?? "Title").foregroundStyle(ink.opacity(0.32)),
                      axis: .vertical)
                .textFieldStyle(.plain)
                .font(titleFont)
                .foregroundStyle(ink)
                .lineLimit(1...2)
                .focused($focus, equals: .title(column.id))
                .onSubmit { addItem(toColumn: index, at: 0) }
                .padding(.horizontal, 10)

            ForEach(column.items) { item in
                tile(item, column: index)
            }

            Button { addItem(toColumn: index) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(ink.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
        .padding(.horizontal, 4)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        // Бросили не на плитку, а на колонку — в конец.
        .dropDestination(for: String.self) { ids, _ in
            drop(ids, toColumn: index, at: column.items.count)
        }
        .contextMenu {
            Button("Add Column") { addColumn() }
            if board.columns.count > 1 {
                Button("Remove Column", role: .destructive) { change { $0.removeColumn(index) } }
            }
        }
    }

    // MARK: - Плитка

    private func tile(_ item: KanbanBoard.Item, column: Int) -> some View {
        KanbanTile(
            text: textBinding(item.id), id: item.id, ink: ink, font: itemFont,
            focus: $focus,
            onDelete: { change { $0.removeItem(item.id) } },
            onSubmit: {
                if let (c, i) = board.location(of: item.id) { addItem(toColumn: c, at: i + 1) }
            },
            onBackspaceWhenEmpty: { deleteEmptyItem(item.id) },
            onDrop: { ids, below in
                guard let (c, i) = board.location(of: item.id) else { return false }
                return drop(ids, toColumn: c, at: below ? i + 1 : i)
            }
        )
    }

    // MARK: - Правки

    private func titleBinding(_ id: KanbanBoard.Column.ID) -> Binding<String> {
        Binding(
            get: { board.columns.first { $0.id == id }?.title ?? "" },
            set: { newValue in
                guard let index = board.columns.firstIndex(where: { $0.id == id }) else { return }
                commit(undoable: false) { $0.setTitle(newValue, ofColumn: index) }
            }
        )
    }

    private func textBinding(_ id: KanbanBoard.Item.ID) -> Binding<String> {
        Binding(
            get: { board.location(of: id).map { board.columns[$0.column].items[$0.index].text } ?? "" },
            set: { newValue in commit(undoable: false) { $0.setText(newValue, of: id) } }
        )
    }

    private func addItem(toColumn column: Int, at index: Int? = nil) {
        var newID: KanbanBoard.Item.ID?
        change {
            Self.adoptHint(&$0, column: column)
            newID = $0.addItem(toColumn: column, at: index)
        }
        if let newID {
            // Фокус — после того, как плитка появилась в иерархии.
            DispatchQueue.main.async { focus = .item(newID) }
        }
    }

    private func addColumn() {
        var newID: KanbanBoard.Column.ID?
        change { newID = $0.addColumn() }
        if let newID { DispatchQueue.main.async { focus = .title(newID) } }
    }

    /// Backspace в пустой плитке: удалить её, фокус — на предыдущую.
    private func deleteEmptyItem(_ id: KanbanBoard.Item.ID) {
        guard let (c, i) = board.location(of: id) else { return }
        let previous: FocusTarget = i > 0 ? .item(board.columns[c].items[i - 1].id) : .title(board.columns[c].id)
        change { $0.removeItem(id) }
        DispatchQueue.main.async { focus = previous }
    }

    private func drop(_ ids: [String], toColumn column: Int, at index: Int) -> Bool {
        guard let raw = ids.first, let id = UUID(uuidString: raw), board.location(of: id) != nil else { return false }
        change {
            Self.adoptHint(&$0, column: column)
            $0.moveItem(id, toColumn: column, at: index)
        }
        return true
    }

    /// В колонке без имени появляется первый пункт — подсказка становится именем.
    private static func adoptHint(_ board: inout KanbanBoard, column: Int) {
        guard board.columns.indices.contains(column), board.columns[column].title.isEmpty,
              board.columns[column].items.isEmpty, let hint = titleHint(column) else { return }
        board.setTitle(hint, ofColumn: column)
    }

    /// Структурная правка (добавить, удалить, перенести) — с отменой.
    private func change(_ edit: (inout KanbanBoard) -> Void) { commit(undoable: true, edit) }

    private func commit(undoable: Bool, _ edit: (inout KanbanBoard) -> Void) {
        let before = board.serialized()
        edit(&board)
        let after = board.serialized()
        guard after != before else { return }
        if undoable { registerUndo(restoring: before) }
        text = after
        onTextChange()
    }

    private func registerUndo(restoring previous: String) {
        undoManager?.registerUndo(withTarget: undoHost) { host in host.apply(previous) }
    }

    /// ⌘Z / ⇧⌘Z: вернуть текст целиком (и записать обратную правку для повтора).
    private func restore(_ previous: String) {
        let current = board.serialized()
        registerUndo(restoring: current)
        guard let parsed = KanbanBoard.parse(previous) else { return }
        board = parsed
        text = previous
        onTextChange()
    }
}

// MARK: - Плитка пункта

/// Плитка: скруглённая подложка с текстом слева. По наведению справа
/// появляются ручка переноса (сверху) и галочка «готово — удалить» (снизу).
private struct KanbanTile: View {
    @Binding var text: String
    let id: KanbanBoard.Item.ID
    let ink: Color
    let font: Font
    var focus: FocusState<KanbanCardView.FocusTarget?>.Binding
    var onDelete: () -> Void
    var onSubmit: () -> Void
    var onBackspaceWhenEmpty: () -> Void
    var onDrop: ([String], _ below: Bool) -> Bool

    @State private var height: CGFloat = 60
    @State private var isDropTargeted = false
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ink.opacity(isDropTargeted ? 0.28 : 0.18))
                .contextMenu { Button("Delete", role: .destructive, action: onDelete) }

            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(ink)
                .focused(focus, equals: .item(id))
                .onSubmit(onSubmit)
                .onKeyPress(.delete) {
                    guard text.isEmpty else { return .ignored }
                    onBackspaceWhenEmpty()
                    return .handled
                }
                // Справа — место под ручку и галочку, чтобы текст не прыгал по наведению.
                .padding(.leading, 16)
                .padding(.trailing, 36)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering {
                VStack {
                    Image(systemName: "circle.grid.2x3.fill")
                        .font(.system(size: 9))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        .draggable(id.uuidString) {
                            Text(text.isEmpty ? " " : text)
                                .font(font).foregroundStyle(ink)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ink.opacity(0.22)))
                        }
                        .help("Drag to another column")
                    Spacer(minLength: 0)
                    Button(action: onDelete) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Done \u{2014} remove")
                }
                .foregroundStyle(ink.opacity(0.85))
                .padding(.trailing, 6)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.opacity)
            }
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { height = proxy.size.height }
                .onChange(of: proxy.size.height) { _, new in height = new }
        })
        .dropDestination(for: String.self) { ids, location in
            onDrop(ids, location.y > height / 2)
        } isTargeted: { isDropTargeted = $0 }
    }
}
