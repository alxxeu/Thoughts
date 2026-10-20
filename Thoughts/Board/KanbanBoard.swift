import Foundation

/// Карточка-виджет «канбан»: колонки с плитками-пунктами. Хранится обычным
/// текстом карточки — первая строка-метка `::: board`, колонки разделяет
/// строка `||`, заголовок колонки — `# …`, пункт — `- …` (продолжение
/// пункта — строки с отступом в два пробела). Так синк, бэкапы, импорт,
/// Spotlight и Ask AI работают с карточкой как с любым другим текстом.
struct KanbanBoard: Equatable {
    static let marker = "::: board"
    static let columnBreak = "||"

    struct Item: Identifiable, Equatable {
        var id = UUID()
        var text: String
    }

    struct Column: Identifiable, Equatable {
        var id = UUID()
        var title: String
        var items: [Item]
    }

    var columns: [Column]

    // MARK: - Текст ↔ модель

    /// Первая строка текста — метка виджета.
    static func isBoard(_ text: String) -> Bool {
        text.prefix(while: { $0 != "\n" }).trimmingCharacters(in: .whitespaces) == marker
    }

    /// nil — это не виджет (нет метки). Разбор терпимый: незнакомая строка
    /// не пропадает, а становится пунктом; пустые строки игнорируются.
    static func parse(_ text: String) -> KanbanBoard? {
        guard isBoard(text) else { return nil }
        let lines = text.components(separatedBy: "\n").dropFirst()
        var columns = [Column(title: "", items: [])]
        var titleAllowed = true // заголовок — только первая непустая строка колонки

        for raw in lines {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line == columnBreak {
                columns.append(Column(title: "", items: []))
                titleAllowed = true
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let last = columns.count - 1

            if titleAllowed, line.hasPrefix("# ") {
                columns[last].title = String(line.dropFirst(2))
            } else if line.hasPrefix("- ") || line == "-" {
                columns[last].items.append(Item(text: String(line.dropFirst(2))))
            } else if line.hasPrefix("  "), !columns[last].items.isEmpty {
                columns[last].items[columns[last].items.count - 1].text += "\n" + line.dropFirst(2)
            } else {
                columns[last].items.append(Item(text: line))
            }
            titleAllowed = false
        }
        return KanbanBoard(columns: columns)
    }

    /// Канонический текст карточки.
    func serialized() -> String {
        let body = columns.map { column -> String in
            var lines: [String] = []
            let title = column.title.replacingOccurrences(of: "\n", with: " ")
            if !title.isEmpty { lines.append("# " + title) }
            for item in column.items {
                let parts = item.text.components(separatedBy: "\n")
                lines.append("- " + parts[0])
                lines += parts.dropFirst().map { "  " + $0 }
            }
            return lines.joined(separator: "\n")
        }
        return Self.marker + "\n" + body.joined(separator: "\n" + Self.columnBreak + "\n")
    }

    // MARK: - Правки

    func location(of itemID: Item.ID) -> (column: Int, index: Int)? {
        for (c, column) in columns.enumerated() {
            if let i = column.items.firstIndex(where: { $0.id == itemID }) { return (c, i) }
        }
        return nil
    }

    /// Новый пустой пункт; `index` — позиция в колонке (nil — в конец). Возвращает его id.
    @discardableResult
    mutating func addItem(toColumn column: Int, at index: Int? = nil, text: String = "") -> Item.ID? {
        guard columns.indices.contains(column) else { return nil }
        let item = Item(text: text)
        let position = min(max(index ?? columns[column].items.count, 0), columns[column].items.count)
        columns[column].items.insert(item, at: position)
        return item.id
    }

    mutating func removeItem(_ id: Item.ID) {
        guard let (c, i) = location(of: id) else { return }
        columns[c].items.remove(at: i)
    }

    /// Пункт — в колонку `column`, на позицию `index` (в координатах колонки до переноса).
    mutating func moveItem(_ id: Item.ID, toColumn column: Int, at index: Int) {
        guard columns.indices.contains(column), let (c, i) = location(of: id) else { return }
        let item = columns[c].items.remove(at: i)
        var position = min(max(index, 0), columns[column].items.count + (c == column ? 1 : 0))
        // Внутри одной колонки индекс «до переноса»: после удаления он сдвигается.
        if c == column, position > i { position -= 1 }
        position = min(position, columns[column].items.count)
        columns[column].items.insert(item, at: position)
    }

    mutating func setText(_ text: String, of id: Item.ID) {
        guard let (c, i) = location(of: id) else { return }
        columns[c].items[i].text = text
    }

    mutating func setTitle(_ title: String, ofColumn column: Int) {
        guard columns.indices.contains(column) else { return }
        columns[column].title = title
    }

    /// Новая колонка справа (id нужен, чтобы сфокусировать её заголовок).
    @discardableResult
    mutating func addColumn(title: String = "") -> Column.ID {
        let column = Column(title: title, items: [])
        columns.append(column)
        return column.id
    }

    /// Колонка удаляется вместе с пунктами; последняя остаётся.
    mutating func removeColumn(_ column: Int) {
        guard columns.count > 1, columns.indices.contains(column) else { return }
        columns.remove(at: column)
    }
}
