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

    /// Курс экрана 3: создать, написать, тег, удалить.
    private func passSandbox(_ model: OnboardingViewModel) {
        model.cardCreated(UUID())
        model.sync(cardExists: true, hasText: true, hasTag: false)
        model.sync(cardExists: true, hasText: true, hasTag: true)
        model.sync(cardExists: false, hasText: false, hasTag: false)
        #expect(model.isSandboxDone)
    }

    @Test func sandboxNeedsAllFourTasksInOrderOfDeletion() {
        let (model, _) = makeModel()
        model.next(); model.next()
        #expect(model.currentTask == .create)
        model.cardCreated(UUID())
        #expect(model.currentTask == .type)
        model.sync(cardExists: true, hasText: true, hasTag: false)
        #expect(model.currentTask == .tag)
        // Удалили раньше тега — нужна новая карточка, текст засчитан.
        model.sync(cardExists: false, hasText: false, hasTag: false)
        #expect(model.currentTask == .create)
        #expect(model.isDone(.type))
        model.next()
        #expect(model.step == .firstCard)
        model.cardCreated(UUID())
        model.sync(cardExists: true, hasText: false, hasTag: true)
        model.sync(cardExists: false, hasText: false, hasTag: false)
        #expect(model.isSandboxDone)
        model.next()
        #expect(model.step == .finish)
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
        // Без курса в карточку дальше нельзя.
        model.next()
        #expect(model.step == .firstCard)
        passSandbox(model)
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
        passSandbox(model)
        model.next(); model.next()
        #expect(box.finished?.0 == OnboardingHome.window)
    }

    @Test func replayKeepsModeUnlessChosenAndAddsNoCheatSheet() {
        let (model, box) = makeModel()
        model.start(currentHome: .window)
        #expect(model.home == .window)
        model.next(); model.next()
        passSandbox(model)
        model.next(); model.next()
        // Подтвердили предвыбранный режим — тот же; шпаргалку второй раз не кладём.
        #expect(box.finished?.0 == OnboardingHome.window)
        #expect(box.finished?.1 == false)
    }
}
