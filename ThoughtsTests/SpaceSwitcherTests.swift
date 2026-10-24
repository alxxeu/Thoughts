import Foundation
import Testing
@testable import Thoughts

@MainActor
struct SpaceSwitcherTests {
    @Test func neighbourSlotWrapsAround() {
        #expect(BoardViewModel.neighbourSlot(of: 9, step: 1) == 1)
        #expect(BoardViewModel.neighbourSlot(of: 1, step: -1) == 9)
        #expect(BoardViewModel.neighbourSlot(of: 4, step: 1) == 5)
    }

    @Test func initialSelectionIsTheCurrentSpace() {
        #expect(SpaceSwitcherSelection.initial(active: 3).slot == 3)
        #expect(SpaceSwitcherSelection.initial(active: 9).slot == 9)
    }

    @Test func selectionMovesInCircle() {
        var selection = SpaceSwitcherSelection(slot: 9)
        selection.move(1)
        #expect(selection.slot == 1)
        selection.move(-2)
        #expect(selection.slot == 8)
    }

    @Test func verticalStepMovesByARowAndWraps() {
        var selection = SpaceSwitcherSelection(slot: 2)
        selection.move(SpaceSwitcherView.columns)
        #expect(selection.slot == 5)
        selection.move(-SpaceSwitcherView.columns * 2)
        #expect(selection.slot == 8)
    }
}

struct SpaceBarSwipeTests {
    @Test func pullIsDampedAndSymmetric() {
        #expect(SpaceBarSwipe.resisted(0) == 0)
        #expect(SpaceBarSwipe.resisted(-50) == -SpaceBarSwipe.resisted(50))
        #expect(SpaceBarSwipe.resisted(40) < 40)
        #expect(SpaceBarSwipe.resisted(10_000) < SpaceBarSwipe.maxPull)
        #expect(SpaceBarSwipe.resisted(200) > SpaceBarSwipe.resisted(100))
    }

    @Test func stepNeedsTheThreshold() {
        #expect(SpaceBarSwipe.step(forRaw: -30) == 0)
        #expect(SpaceBarSwipe.step(forRaw: -SpaceBarSwipe.threshold) == 1)
        #expect(SpaceBarSwipe.step(forRaw: SpaceBarSwipe.threshold + 10) == -1)
    }
}

struct SpaceBarDestinationTests {
    @Test func ringWithDesktop() {
        #expect(SpaceBarSwipe.destination(current: 1, step: -1, hasDesktop: true) == .desktop)
        #expect(SpaceBarSwipe.destination(current: nil, step: 1, hasDesktop: true) == .space(1))
        #expect(SpaceBarSwipe.destination(current: nil, step: -1, hasDesktop: true) == .space(9))
        #expect(SpaceBarSwipe.destination(current: 9, step: 1, hasDesktop: true) == .desktop)
        #expect(SpaceBarSwipe.destination(current: 4, step: 1, hasDesktop: true) == .space(5))
    }

    @Test func ringWithoutDesktopWrapsAtNine() {
        #expect(SpaceBarSwipe.destination(current: 1, step: -1, hasDesktop: false) == .space(9))
        #expect(SpaceBarSwipe.destination(current: 9, step: 1, hasDesktop: false) == .space(1))
    }
}

struct SpaceBarDotPullTests {
    @Test func pullFollowsSwipeAndIsClamped() {
        #expect(SpaceBarSwipe.dotPull(forRaw: 0) == 0)
        #expect(SpaceBarSwipe.dotPull(forRaw: -SpaceBarSwipe.threshold / 2) == -0.5)
        #expect(SpaceBarSwipe.dotPull(forRaw: SpaceBarSwipe.threshold * 3) == 1)
    }
}
