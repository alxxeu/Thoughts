import Foundation
import Testing
@testable import Thoughts

@MainActor
struct OnboardingFlowTests {
    private func makeModel() -> (OnboardingViewModel, Box) {
        let model = OnboardingViewModel(isActive: true)
        let box = Box()
        model.markCompleted = { box.completed = true }
        model.onFinish = { home, firstRun in box.finished = (home, firstRun) }
        return (model, box)
    }

    final class Box {
        var completed = false
        var finished: (OnboardingHome?, Bool)?
    }

    @Test func firstRunGoesThroughAllStepsAndAppliesDesktopByDefault() {
        let (model, box) = makeModel()
        #expect(model.step == .hook)
        model.next()
        #expect(model.step == .home)
        model.next()
        #expect(model.step == .firstCard)
        // Без карточки дальше нельзя.
        model.next()
        #expect(model.step == .firstCard)
        model.handle(.cardMoved)
        #expect(!model.didCreateCard)
        model.handle(.cardCreated)
        #expect(model.didCreateCard)
        model.next()
        #expect(model.step == .finish)
        model.next()
        #expect(!model.isActive)
        #expect(box.completed)
        #expect(box.finished?.0 == OnboardingHome.desktop)
        #expect(box.finished?.1 == true)
    }

    @Test func backAndChoice() {
        let (model, box) = makeModel()
        model.back()
        #expect(model.step == .hook) // с первого экрана назад некуда
        model.next()
        model.choose(.window)
        model.back()
        #expect(model.step == .hook)
        model.next(); model.next()
        model.handle(.cardCreated)
        model.next(); model.next()
        #expect(box.finished?.0 == OnboardingHome.window)
    }

    @Test func replayKeepsModeUnlessChosenAndAddsNoCheatSheet() {
        let (model, box) = makeModel()
        model.start(currentHome: .window)
        #expect(model.home == .window)
        model.next(); model.next()
        model.handle(.cardCreated)
        model.next(); model.next()
        // Подтвердили предвыбранный режим — тот же; шпаргалку второй раз не кладём.
        #expect(box.finished?.0 == OnboardingHome.window)
        #expect(box.finished?.1 == false)
    }
}
