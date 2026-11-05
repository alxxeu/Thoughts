import CoreGraphics

/// Готовые карточки для правого клика по пустому месту доски. Текст — обычный
/// Markdown карточки; виджеты начинаются с метки `::: board` (см. KanbanBoard).
/// Размер — в клетках сетки: `k × 60 − 16` pt.
struct CardTemplate: Identifiable {
    let id: String
    let name: String
    /// Короткий комментарий в меню: для чего этот вариант.
    let note: String
    let text: String
    let columns: Int
    let rows: Int
    var tag: CardTagColor? = nil

    var menuTitle: String { "\(name) \u{2014} \(note)" }

    var size: CGSize {
        let step = BoardViewModel.cardSizeStep, gap = BoardViewModel.cardGap
        return CGSize(width: CGFloat(columns) * step - gap, height: CGFloat(rows) * step - gap)
    }

    /// Доска из `count` колонок. В первой уже есть пустой пункт (курсор встаёт в
    /// него) и имя Plan; имена остальных (To go / Ready / Done) — полупрозрачная
    /// подсказка, она становится настоящей, когда в колонку добавляют пункт или
    /// вписывают своё имя.
    private static func board(id: String, name: String, note: String, count: Int, cells: Int) -> CardTemplate {
        let lines = ["::: board", "## Plan", "- "] + Array(repeating: "||", count: count - 1)
        return CardTemplate(id: id, name: name, note: note, text: lines.joined(separator: "\n"), columns: cells, rows: 6)
    }

    static let all: [CardTemplate] = [
        board(id: "board1", name: "1 Column", note: "good for a daily plan", count: 1, cells: 6),
        board(id: "board2", name: "2 Columns", note: "simple to-do", count: 2, cells: 9),
        board(id: "board3", name: "3 Columns", note: "regular kanban", count: 3, cells: 12),
        board(id: "board4", name: "4 Columns", note: "workflow with a review step", count: 4, cells: 14),
    ]

    /// Обычный канбан из трёх колонок.
    static var kanban: CardTemplate { all[2] }

    /// «New Card» — первый пункт правого клика: пустая карточка 4×3 клетки,
    /// как у Quick Capture.
    static let blank = CardTemplate(id: "blank", name: "New Card", note: "", text: "", columns: 4, rows: 3)

    var isBoard: Bool { text.hasPrefix("::: board") }
}

/// Шаблон в правом клике и в Settings → Plugins → Templates. Один шаблон может
/// иметь несколько вариантов (канбан на 1–4 колонки) — тогда в меню это
/// подменю, а в настройках — одна строка с одним переключателем.
struct TemplateGroup: Identifiable {
    let id: String
    /// Имя в настройках.
    let name: String
    /// Пункт меню (у шаблона с вариантами — заголовок подменю).
    let menuTitle: String
    let variants: [CardTemplate]

    static let kanban = TemplateGroup(id: "kanban", name: "Kanban", menuTitle: "New Kanban Card", variants: CardTemplate.all)

    /// Шаблон из одного варианта (файл из папки шаблонов).
    init(_ template: CardTemplate) {
        self.init(id: template.id, name: template.name, menuTitle: template.name, variants: [template])
    }

    init(id: String, name: String, menuTitle: String, variants: [CardTemplate]) {
        self.id = id
        self.name = name
        self.menuTitle = menuTitle
        self.variants = variants
    }
}
