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

    /// Три пустые колонки: их имена (Plan / To go / Ready) показываются
    /// полупрозрачной подсказкой и становятся настоящими, когда в колонку
    /// добавляют пункт или вписывают своё имя.
    static let kanban = CardTemplate(
        id: "kanban", name: "New Kanban Card",
        text: "::: board\n||\n||",
        columns: 10, rows: 6
    )
}
