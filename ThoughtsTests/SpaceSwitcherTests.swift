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

    @Test func initialSelectionIsThePreviousSpace() {
        #expect(SpaceSwitcherSelection.initial(active: 3, previous: 7).slot == 7)
        // Ещё не переключались — следующий по кругу.
        #expect(SpaceSwitcherSelection.initial(active: 9, previous: nil).slot == 1)
        #expect(SpaceSwitcherSelection.initial(active: 3, previous: 3).slot == 4)
    }

    @Test func selectionMovesInCircle() {
        var selection = SpaceSwitcherSelection(slot: 9)
        selection.move(1)
        #expect(selection.slot == 1)
        selection.move(-2)
        #expect(selection.slot == 8)
    }
}
