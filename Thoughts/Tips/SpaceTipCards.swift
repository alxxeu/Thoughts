import CoreGraphics
import Foundation

/// Слой 3 обучения: при первом заходе в пустой Space 2–9 там появляется одна
/// карточка с советом — как подсказки на загрузочных экранах в играх. Обычная
/// карточка: с тегом, её можно удалить. Desktop Overlay и теги здесь не
/// объясняем — это делают онбординг и подсказки по ходу.
enum SpaceTipCards {
    static let texts: [Int: String] = [
        2: """
        # Kanban boards
        Right-click an empty spot \u{2192} **New Kanban Card** and pick 1\u{2013}4 columns.
        - Add tiles with **+**
        - Drag them between columns
        - Hold the check to finish one
        """,
        3: """
        # Write in Markdown
        **bold**, *italic*, `code`, headings with `#`, tasks with `- [ ]`, quotes with `>`.

        Every style is also in the **Format** menu and in the right-click menu of a card.
        """,
        4: """
        # All your Spaces
        Hold **\u{2325}** and press **Tab** to see every Space at once \u{2014} release to jump there.

        **\u{2325}1\u{2013}9** opens one directly, **\u{2325}\u{2190} \u{2325}\u{2192}** goes next door. Click the name at the top to rename a Space.
        """,
        5: """
        # Quick Capture
        Press **\u{2303}\u{2325}N** in any app to jot down a card without switching to Thoughts. It lands in the current Space.

        Change the shortcut in Settings \u{2192} Shortcuts.
        """,
        6: """
        # The Space bar
        The bar at the top of every Space:
        - **Name** \u{2014} click to rename the Space
        - **Ask AI** \u{2014} ask about everything here; the answer arrives as a card
        - **Tidy Cards** \u{2014} lines your cards up neatly
        - **Clear Space** \u{2014} deletes every card here (asks first)

        Hover the bar and click the gear to hide icons or drag them into your own order.
        """,
        7: """
        # Focus on one card
        Click into a card and press **\u{2318}F** \u{2014} everything else steps back. **Esc** brings it all back.

        Right-click text \u{2192} **Ask AI** to ask about a selection or the whole card.
        """,
        8: """
        # Space Lock
        Keep a whole Space private:
        1. Turn on **Passcode** in Settings \u{2192} Security
        2. Choose which Spaces it protects
        3. Press **\u{2318}L** to lock the current one

        Unlock with your passcode or Touch ID. Auto-Lock locks it again after a while.
        """,
        9: """
        # Keep your notes safe
        **Sync with iCloud** keeps your Spaces on all your Macs, end-to-end encrypted.

        **Export Backup** saves everything to a file, optionally with a password. Both are in Settings \u{2192} General.
        """
    ]

    /// Можно ли положить совет в этот Space: есть текст, Space пустой и не
    /// защищён, совета ещё не было, тур пройден, подсказки включены и синк
    /// выключен (иначе каждый Mac положил бы свою копию).
    static func shouldAdd(slot: Int, isEmpty: Bool, isProtected: Bool, isSyncEnabled: Bool, state: TipsState) -> Bool {
        texts[slot] != nil && isEmpty && !isProtected && !isSyncEnabled
            && state.isEnabled && !state.isPaused && state.hasCompletedTour() && !state.spaceCardSlots.contains(slot)
    }

    static func addIfNeeded(slot: Int, viewModel: BoardViewModel, state: TipsState = .shared) {
        let isProtected = viewModel.workspaces.first { $0.slot == slot }?.isProtected ?? false
        guard shouldAdd(slot: slot, isEmpty: viewModel.cards(inSlot: slot).isEmpty, isProtected: isProtected,
                        isSyncEnabled: CloudSyncSettings.shared.isEnabled, state: state),
              let text = texts[slot] else { return }
        state.markSpaceCard(slot)
        let step = BoardViewModel.cardSizeStep, gap = BoardViewModel.cardGap
        let size = CGSize(width: 6 * step - gap, height: 7 * step - gap)
        let canvas = viewModel.lastCanvasSize == .zero ? CGSize(width: 1000, height: 700) : viewModel.lastCanvasSize
        let topInset = viewModel.desktopOverlay.isEnabled ? BoardViewModel.desktopOverlayTopInset : BoardViewModel.topCreationLimit
        let origin = BoardViewModel.firstFreeOrigin(size: size, among: [], canvasSize: canvas, topInset: topInset)
        let card = viewModel.addCard(at: origin, size: size, slot: slot, text: text)
        card.tagColor = .blue
        viewModel.scheduleDebouncedSave()
    }
}
