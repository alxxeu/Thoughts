import CoreGraphics

/// Готовые карточки для правого клика по пустому месту доски. Текст — обычный
/// Markdown карточки; виджеты начинаются с метки `::: board` (см. KanbanBoard).
/// Размер — в клетках сетки: `k × 60 − 16` pt.
struct CardTemplate: Identifiable {
    let id: String
    let name: String
    let text: String
    let columns: Int
    let rows: Int
    var tag: CardTagColor? = nil

    var size: CGSize {
        let step = BoardViewModel.cardSizeStep, gap = BoardViewModel.cardGap
        return CGSize(width: CGFloat(columns) * step - gap, height: CGFloat(rows) * step - gap)
    }

    static let all: [CardTemplate] = [kanban]

    /// Три колонки. В первой уже есть пустой пункт (курсор встаёт в него) и
    /// имя Plan; имена To go / Ready — полупрозрачная подсказка, она становится
    /// настоящей, когда в колонку добавляют пункт или вписывают своё имя.
    static let kanban = CardTemplate(
        id: "kanban", name: "New Kanban Card",
        text: "::: board\n# Plan\n- \n||\n||",
        columns: 12, rows: 6
    )
}
