import Foundation
import Testing
@testable import Thoughts

@MainActor
struct TipsTests {
    private func makeState(tourDone: Bool = true) -> TipsState {
        let name = "tips-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let state = TipsState(defaults: defaults)
        state.hasCompletedTour = { tourDone }
        return state
    }

    @Test func toastShowsOncePerTipAndOnePerSession() {
        let state = makeState()
        state.offer(.spaceSwitch)
        #expect(state.currentToast == .spaceSwitch)
        state.dismissToast()
        // В этот запуск плашек больше нет.
        state.offer(.moveResize)
        #expect(state.currentToast == nil)
        #expect(state.seen == [.spaceSwitch])
        #expect(!state.shouldShow(.spaceSwitch))
        #expect(state.shouldShow(.moveResize))
    }

    @Test func noTipsDuringTourOrWhenDisabled() {
        let duringTour = makeState(tourDone: false)
        duringTour.offer(.spaceSwitch)
        #expect(duringTour.currentToast == nil)
        let disabled = makeState()
        disabled.isEnabled = false
        #expect(!disabled.shouldShow(.tagColors))
    }

    @Test func resetBringsTipsAndCardsBack() {
        let state = makeState()
        state.markSeen(.tagColors)
        state.markSpaceCard(4)
        state.reset()
        #expect(state.shouldShow(.tagColors))
        #expect(state.spaceCardSlots.isEmpty)
    }

    @Test func spaceTipCardConditions() {
        let state = makeState()
        func ok(_ slot: Int, empty: Bool = true, protected: Bool = false, sync: Bool = false) -> Bool {
            SpaceTipCards.shouldAdd(slot: slot, isEmpty: empty, isProtected: protected, isSyncEnabled: sync, state: state)
        }
        #expect(ok(2))
        #expect(!ok(1)) // в первом Space — шпаргалка онбординга, совета нет
        #expect(!ok(3, empty: false))
        #expect(!ok(3, protected: true))
        #expect(!ok(3, sync: true))
        state.markSpaceCard(5)
        #expect(!ok(5))
        #expect(SpaceTipCards.texts.keys.sorted() == Array(2...9))
    }
}
