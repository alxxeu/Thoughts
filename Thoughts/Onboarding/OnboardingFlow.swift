import AppKit
import Observation

/// Флаг завершения тура — UserDefaults, тот же стиль ключей, что в SecuritySettings.
enum OnboardingState {
    private static let hasCompletedKey = "onboarding.hasCompletedTour"

    static var hasCompletedTour: Bool {
        get { UserDefaults.standard.bool(forKey: hasCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedKey) }
    }
}

/// Реальные действия пользователя на канве. Тур ждёт только `cardCreated`
/// (экран «первая карточка»); остальные приходят из CardView/TagPopoverView и
/// пригодятся подсказкам по ходу работы.
enum OnboardingGateEvent {
    case cardCreated, cardMoved, cardResized, tagColorSet, spoilerSet, spaceSwitched
}

/// Четыре экрана тура. Пропустить нельзя (решение автора) — поэтому он короткий.
enum OnboardingStep: Int, CaseIterable {
    /// Крючок: анимация сама показывает, что такое Thoughts.
    case hook
    /// Где жить Thoughts: окно или рабочий стол.
    case home
    /// Вводный курс в карточку — в «окне» в настоящий Space: создать, написать,
    /// поставить тег, удалить.
    case firstCard
    /// Финал: режим применяется, на доске остаётся шпаргалка.
    case finish
}

/// Задания экрана «первая карточка», по порядку.
enum SandboxTask: Int, CaseIterable {
    case create, type, tag, delete
}

/// Где живёт Thoughts — выбор на втором экране.
enum OnboardingHome: Equatable {
    case window, desktop
}

/// Состояние тура. Не держит BoardViewModel: применение выбора и шпаргалку делает
/// ContentView в `onFinish`.
@Observable
final class OnboardingViewModel {
    private(set) var step: OnboardingStep = .hook
    var isActive: Bool
    /// По умолчанию — рабочий стол: это базовая фишка Thoughts.
    var home: OnboardingHome = .desktop
    /// Пользователь сам выбрал режим на экране 2 (при Replay без выбора режим не трогаем).
    private(set) var didChooseHome = false
    /// Карточка экрана 3 (в «окне» в Space) и что с ней уже сделали.
    private(set) var sandboxCardID: UUID?
    private(set) var didType = false
    private(set) var didTag = false
    private(set) var didDelete = false
    /// Все четыре задания экрана 3 выполнены.
    var isSandboxDone: Bool { didDelete }
    /// Тур идёт впервые (не Replay): тогда режим применяется всегда и кладётся шпаргалка.
    private(set) var isFirstRun: Bool

    /// Конец тура: (выбранный режим или nil — не менять, первый ли это запуск).
    @ObservationIgnored var onFinish: (OnboardingHome?, Bool) -> Void = { _, _ in }
    @ObservationIgnored var markCompleted: () -> Void = { OnboardingState.hasCompletedTour = true }

    init(isActive: Bool = !OnboardingState.hasCompletedTour) {
        self.isActive = isActive
        isFirstRun = isActive
    }

    /// Тур с начала, текущий режим предвыбран.
    func start(currentHome: OnboardingHome) {
        step = .hook
        home = currentHome
        didChooseHome = false
        resetSandbox()
        isFirstRun = false
        isActive = true
    }

    /// Задания экрана 3: выполнено ли.
    func isDone(_ task: SandboxTask) -> Bool {
        switch task {
        case .create: return sandboxCardID != nil || didDelete
        case .type: return didType
        case .tag: return didTag
        case .delete: return didDelete
        }
    }

    /// Текущее задание — первое невыполненное.
    var currentTask: SandboxTask? { SandboxTask.allCases.first { !isDone($0) } }

    private func resetSandbox() {
        sandboxCardID = nil
        didType = false
        didTag = false
        didDelete = false
    }

    var canGoBack: Bool { step != .hook }

    func choose(_ home: OnboardingHome) {
        self.home = home
        didChooseHome = true
    }

    /// Return / Space / Continue.
    func next() {
        guard isActive else { return }
        switch step {
        case .hook: step = .home
        case .home:
            // Подтверждение предвыбранного «Desktop» тоже выбор.
            didChooseHome = true
            step = .firstCard
        case .firstCard:
            guard isSandboxDone else { return }
            step = .finish
        case .finish: complete()
        }
    }

    /// ← / Back.
    func back() {
        guard isActive, canGoBack else { return }
        switch step {
        case .home: step = .hook
        case .firstCard:
            resetSandbox()
            step = .home
        case .finish: step = .firstCard
        default: break
        }
    }

    /// События канвы (перенос, тег…) тур больше не ждёт — курс экрана 3 следит за
    /// своей карточкой сам (`cardCreated`, `sync`).
    func handle(_ event: OnboardingGateEvent) {}

    /// Карточку создали в «окне» экрана 3.
    func cardCreated(_ id: UUID) {
        guard isActive, step == .firstCard, sandboxCardID == nil, !didDelete else { return }
        sandboxCardID = id
        reward()
    }

    /// Состояние карточки экрана 3 (её нет — значит, удалили). Тег и текст
    /// засчитываются насовсем; удалили раньше, чем написали и поставили тег, —
    /// нужна новая карточка.
    func sync(cardExists: Bool, hasText: Bool, hasTag: Bool) {
        guard isActive, step == .firstCard, sandboxCardID != nil, !didDelete else { return }
        if cardExists {
            if hasText, !didType { didType = true; reward() }
            if hasTag, !didTag { didTag = true; reward() }
        } else if didType && didTag {
            didDelete = true
            reward()
        } else {
            sandboxCardID = nil
        }
    }

    private func reward() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func complete() {
        markCompleted()
        isActive = false
        onFinish(isFirstRun || didChooseHome ? home : nil, isFirstRun)
    }
}
