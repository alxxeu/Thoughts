import CoreGraphics

/// Готовые карточки для «New from Template» (правый клик по пустому месту
/// доски). Текст — обычный Markdown карточки; виджеты начинаются с метки
/// `::: board` (см. KanbanBoard). Размер — в клетках сетки: `k × 60 − 16` pt.
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

    static let all: [CardTemplate] = [kanban, todo, meeting]

    static let kanban = CardTemplate(
        id: "kanban", name: "Kanban",
        text: "::: board\n# Plan\n||\n# To go\n||\n# Ready",
        columns: 10, rows: 6
    )

    static let todo = CardTemplate(
        id: "todo", name: "To-Do",
        text: "::: board\n# Today\n||\n# This week",
        columns: 7, rows: 6
    )

    static let meeting = CardTemplate(
        id: "meeting", name: "Meeting / Standup",
        text: "::: board\n# Yesterday\n||\n# Today\n||\n# Blockers",
        columns: 10, rows: 6
    )
}
