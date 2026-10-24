import Foundation
import CoreGraphics

/// Карточка-шпаргалка, которая остаётся на доске после онбординга: самое нужное
/// в одном месте. Обычная карточка — её можно править и удалить.
enum CheatSheetCard {
    static let text = """
    # Cheat sheet
    - **Drag** on empty space \u{2014} new card; drag a card **by its top** to move it
    - **Right-click** empty space \u{2014} New Card, Kanban
    - **\u{2325}1\u{2013}9**, **\u{2325}\u{2190} \u{2325}\u{2192}** \u{2014} switch Spaces
    - **\u{2325}Tab** \u{2014} all Spaces
    - **\u{2303}1\u{2013}7** \u{2014} color tag
    - **\u{2318}F** or **pinch out** \u{2014} focus on a card
    - **\u{2318}L** \u{2014} lock the Space
    - **\u{2325}D** \u{2014} show the desktop
    - **\u{2303}\u{2325}N** \u{2014} Quick Capture from any app

    > Delete this card when you know it by heart.
    """

    /// 6 × 7 клеток — в первое свободное место текущего Space, с жёлтым тегом.
    static func add(to viewModel: BoardViewModel) {
        let step = BoardViewModel.cardSizeStep, gap = BoardViewModel.cardGap
        let size = CGSize(width: 6 * step - gap, height: 7 * step - gap)
        let canvas = viewModel.lastCanvasSize == .zero ? CGSize(width: 1000, height: 700) : viewModel.lastCanvasSize
        let topInset = viewModel.desktopOverlay.isEnabled ? BoardViewModel.desktopOverlayTopInset : BoardViewModel.topCreationLimit
        let origin = BoardViewModel.firstFreeOrigin(size: size, among: viewModel.cards, canvasSize: canvas, topInset: topInset)
        let card = viewModel.addCard(at: origin, size: size, text: text)
        card.tagColor = .yellow
        viewModel.scheduleDebouncedSave()
    }
}
