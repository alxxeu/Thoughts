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

    @Test func nextToastWaitsForTheActionAndThreeMinutes() {
        let state = makeState()
        var clock = Date(timeIntervalSince1970: 1_000)
        state.now = { clock }

        state.offer(.spaceSwitch)
        #expect(state.currentToast == .spaceSwitch)
        // Пока действие из плашки не выполнено — новых нет.
        state.offer(.focusMode)
        #expect(state.currentToast == .spaceSwitch)

        // Переключили Space — плашка закрылась, пошла пауза.
        state.noteAction(for: .focusMode) // чужое действие ничего не меняет
        #expect(state.currentToast == .spaceSwitch)
        state.noteAction(for: .spaceSwitch)
        #expect(state.currentToast == nil)

        clock += 120
        state.offer(.focusMode)
        #expect(state.currentToast == nil)
        clock += 61
        state.offer(.focusMode)
        #expect(state.currentToast == .focusMode)
        #expect(!state.shouldShow(.spaceSwitch))
    }

    @Test func gotItAlsoStartsThePause() {
        let state = makeState()
        var clock = Date(timeIntervalSince1970: 1_000)
        state.now = { clock }
        state.offer(.askAI)
        state.dismissToast()
        state.offer(.focusMode)
        #expect(state.currentToast == nil)
        clock += 180
        state.offer(.focusMode)
        #expect(state.currentToast == .focusMode)
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
        state.reset()
        #expect(state.shouldShow(.tagColors))
    }
}
