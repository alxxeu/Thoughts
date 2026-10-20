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
    /// Идёт перенос плитки: свой жест (не системный drag-and-drop — тот давал
    /// текстовым полям «принять» id плитки как строку).
    @State private var dragging: DragState?
    @State private var tileFrames: [UUID: CGRect] = [:]
    @State private var isCardHovered = false

    private struct DragState: Equatable {
        var itemID: KanbanBoard.Item.ID
        var text: String
        var pointer: CGPoint
        var width: CGFloat
    }

    fileprivate struct TileFramesKey: PreferenceKey {
        static var defaultValue: [UUID: CGRect] = [:]
        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue()) { $1 }
        }
    }
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

    private static let sidePadding: CGFloat = 10
    /// Подсказки имён первых колонок — «намёк», что их можно переименовать.
    private static let titleHints = ["Plan", "To go", "Ready"]
    private static func titleHint(_ column: Int) -> String? {
        titleHints.indices.contains(column) ? titleHints[column] : nil
    }
    private var ink: Color { Color(nsColor: typography.color) }
    private var itemFont: Font { Font(typography.font as CTFont) }
    private var titleFont: Font {
        let size = typography.font.pointSize * 1.3 // как заголовок второго уровня
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
            .coordinateSpace(name: "kanban")
            .onPreferenceChange(TileFramesKey.self) { tileFrames = $0 }
            .overlay(alignment: .topLeading) { dragGhost }
            .frame(minHeight: max(cardSize.height - 44, 60), alignment: .top)
            .padding(.horizontal, Self.sidePadding)
            // Как у текстовой карточки (отступ 20 pt) — заголовок на той же высоте.
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .onHover { isCardHovered = $0 }
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
            if wants, focus == nil { focusFirstItem() }
        }
        .onAppear {
            undoHost.apply = { restore($0) }
            if isFocused { focusFirstItem() }
        }
    }

    // MARK: - Колонка

    private func columnView(_ column: KanbanBoard.Column, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                .padding(.horizontal, 4)

            ForEach(Array(column.items.enumerated()), id: \.element.id) { position, item in
                tile(item, column: index, position: position, isLast: position == column.items.count - 1)
            }

            KanbanPlusButton(ink: ink, isVisible: isCardHovered || isFocused || dragging != nil) {
                addItem(toColumn: index)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            // Пустая колонка: линия вставки — над «+».
            .overlay(alignment: .top) {
                if column.items.isEmpty { dropIndicator(column: index, position: 0).offset(y: -6) }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Add Column") { addColumn() }
            if board.columns.count > 1 {
                Button("Remove Column", role: .destructive) { change { $0.removeColumn(index) } }
            }
        }
    }

    // MARK: - Плитка

    private func tile(_ item: KanbanBoard.Item, column: Int, position: Int, isLast: Bool) -> some View {
        KanbanTile(
            text: textBinding(item.id), id: item.id, ink: ink, font: itemFont,
            focus: $focus,
            onDelete: { change { $0.removeItem(item.id) } },
            onSubmit: {
                if let (c, i) = board.location(of: item.id) { addItem(toColumn: c, at: i + 1) }
            },
            onBackspaceWhenEmpty: { deleteEmptyItem(item.id) },
            isBeingDragged: dragging?.itemID == item.id,
            onDragChanged: { pointer in
                dragging = DragState(itemID: item.id, text: item.text, pointer: pointer, width: tileFrames[item.id]?.width ?? 160)
            },
            onDragEnded: { pointer in finishDrag(item.id, at: pointer) }
        )
        // Мягкое появление и исчезновение (галочка «готово», «+»).
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)),
            removal: .opacity.combined(with: .scale(scale: 0.9))
        ))
        // Линия вставки — на стыке плиток (поверх, макет не двигает).
        .overlay(alignment: .top) { dropIndicator(column: column, position: position).offset(y: -4.5) }
        .overlay(alignment: .bottom) {
            if isLast { dropIndicator(column: column, position: position + 1).offset(y: 4.5) }
        }
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

    /// Фокус — в первый пункт первой колонки (или в её имя, если пунктов нет).
    private func focusFirstItem() {
        guard let first = board.columns.first else { return }
        DispatchQueue.main.async {
            focus = first.items.first.map { .item($0.id) } ?? .title(first.id)
        }
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

    // MARK: - Перенос плитки

    /// Колонка и позиция в ней (в координатах до переноса), куда попадёт плитка.
    private func dropTarget(at pointer: CGPoint) -> (column: Int, index: Int) {
        let count = board.columns.count
        let width = max((cardSize.width - Self.sidePadding * 2) / CGFloat(count), 80)
        let column = min(max(Int((pointer.x / width).rounded(.down)), 0), count - 1)
        let above = board.columns[column].items.filter { (tileFrames[$0.id]?.midY ?? 0) < pointer.y }.count
        return (column, above)
    }

    @ViewBuilder
    private func dropIndicator(column: Int, position: Int) -> some View {
        if let dragging, dropTarget(at: dragging.pointer) == (column, position) {
            Capsule().fill(ink.opacity(0.6)).frame(height: 3).padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private var dragGhost: some View {
        if let dragging {
            Text(dragging.text.isEmpty ? " " : dragging.text)
                .font(itemFont).foregroundStyle(ink)
                .lineLimit(3)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(width: dragging.width, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(ink.opacity(0.3)))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                .position(x: dragging.pointer.x, y: dragging.pointer.y)
                .allowsHitTesting(false)
        }
    }

    private func finishDrag(_ id: KanbanBoard.Item.ID, at pointer: CGPoint) {
        dragging = nil
        let target = dropTarget(at: pointer)
        change {
            Self.adoptHint(&$0, column: target.column)
            $0.moveItem(id, toColumn: target.column, at: target.index)
        }
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
        // Структурные правки (добавить, убрать, перенести) — плавно; набор текста — без анимации.
        if undoable {
            withAnimation(.easeInOut(duration: 0.24)) { edit(&board) }
        } else {
            edit(&board)
        }
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

/// Плитка: скруглённая подложка с текстом слева. Переносится за невидимую
/// подложку; по наведению справа внизу появляется галочка «готово — удалить»
/// (срабатывает при удержании) (лежит поверх плитки и не меняет её размер).
private struct KanbanTile: View {
    @Binding var text: String
    let id: KanbanBoard.Item.ID
    let ink: Color
    let font: Font
    var focus: FocusState<KanbanCardView.FocusTarget?>.Binding
    var onDelete: () -> Void
    var onSubmit: () -> Void
    var onBackspaceWhenEmpty: () -> Void
    var isBeingDragged: Bool
    var onDragChanged: (CGPoint) -> Void
    var onDragEnded: (CGPoint) -> Void

    @State private var isHovering = false
    @State private var isPressingDone = false
    @State private var doneProgress: CGFloat = 0

    var body: some View {
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
            // Отступы симметричны; плитку переносят за любое место подложки вне поля ввода
            // (то есть за поля вокруг текста) — как карточку за её кромку.
            // Справа шире — место под галочку, чтобы текст не прыгал по наведению.
            .padding(.leading, 14)
            .padding(.trailing, 24)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(ink.opacity(0.18))
                    .contextMenu { Button("Delete", role: .destructive, action: onDelete) }
                    .onHover { inside in
                        if inside { NSCursor.arrow.set() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .named("kanban"))
                            .onChanged { onDragChanged($0.location) }
                            .onEnded { onDragEnded($0.location) }
                    )
            )
            .overlay(alignment: .bottomTrailing) { doneButton.padding(3) }
            .opacity(isBeingDragged ? 0.35 : 1)
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .background(GeometryReader { proxy in
                Color.clear.preference(
                    key: KanbanCardView.TileFramesKey.self,
                    value: [id: proxy.frame(in: .named("kanban"))]
                )
            })
    }

    private var controlsVisible: Bool { isHovering || isBeingDragged }

    /// Галочка «готово»: удаляет только при удержании — пока держат, она
    /// плавно заливается зелёным (как кружок у крестика карточки), отпустили
    /// раньше — откатывается. Мягкая защита от случайного удаления.
    private var doneButton: some View {
        ZStack {
            KanbanCheckmark()
                .stroke(ink.opacity(isPressingDone ? 0.45 : 0.7), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            KanbanCheckmark()
                .trim(from: 0, to: doneProgress)
                .stroke(Self.doneGreen, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 12, height: 10)
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.arrow.set() }
        }
        .onLongPressGesture(minimumDuration: Self.doneHoldDuration, maximumDistance: 10, perform: {
            Task { @MainActor in
                onDelete()
                resetDone()
            }
        }, onPressingChanged: { pressing in
            if pressing {
                isPressingDone = true
                withAnimation(.linear(duration: Self.doneHoldDuration)) { doneProgress = 1 }
            } else {
                resetDone()
            }
        })
        .help("Hold to mark as done")
        .opacity(controlsVisible ? 1 : 0)
        .allowsHitTesting(controlsVisible)
    }

    private static let doneGreen = Color(red: 0.32, green: 0.84, blue: 0.47)
    private static let doneHoldDuration: Double = 0.6

    private func resetDone() {
        isPressingDone = false
        withAnimation(.easeOut(duration: 0.12)) { doneProgress = 0 }
    }
}

/// Галочка из двух штрихов — её можно «дорисовывать» через trim.
private struct KanbanCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

// MARK: - Кнопка «+»

/// «+» без подложки: круг появляется по наведению, а у карточки вне фокуса
/// кнопки нет совсем.
private struct KanbanPlusButton: View {
    let ink: Color
    let isVisible: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ink.opacity(0.7))
                .frame(width: 34, height: 34)
                .background(Circle().fill(ink.opacity(isHovering ? 0.14 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.easeOut(duration: 0.15), value: isVisible)
    }
}
