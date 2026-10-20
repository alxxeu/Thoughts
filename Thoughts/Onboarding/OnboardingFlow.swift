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
    /// Первая карточка на настоящей доске — с наградой.
    case firstCard
    /// Финал: режим применяется, на доске остаётся шпаргалка.
    case finish
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
    /// Первая карточка создана — на экране 3 вместо подсказки награда и «Continue».
    private(set) var didCreateCard = false
    /// Тур идёт впервые (не Replay): тогда режим применяется всегда и кладётся шпаргалка.
    private(set) var isFirstRun: Bool

    /// Конец тура: (выбранный режим или nil — не менять, первый ли это запуск).
    @ObservationIgnored var onFinish: (OnboardingHome?, Bool) -> Void = { _, _ in }
    @ObservationIgnored var markCompleted: () -> Void = { OnboardingState.hasCompletedTour = true }

    init(isActive: Bool = !OnboardingState.hasCompletedTour) {
        self.isActive = isActive
        isFirstRun = isActive
    }

    /// Replay из Help / Settings — с начала, текущий режим предвыбран.
    func start(currentHome: OnboardingHome) {
        step = .hook
        home = currentHome
        didChooseHome = false
        didCreateCard = false
        isFirstRun = false
        isActive = true
    }

    /// Экран «первая карточка» — без панели поверх доски: канва принимает драг, а
    /// потом в карточке можно печатать (Return там — перевод строки, не «дальше»).
    var isWaitingOnCanvas: Bool { step == .firstCard }

    var canGoBack: Bool { step != .hook && step != .firstCard }

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
            guard didCreateCard else { return }
            step = .finish
        case .finish: complete()
        }
    }

    /// ← / Back.
    func back() {
        guard isActive, canGoBack else { return }
        switch step {
        case .home: step = .hook
        case .finish: step = .firstCard
        default: break
        }
    }

    func handle(_ event: OnboardingGateEvent) {
        guard isActive, event == .cardCreated, step == .firstCard, !didCreateCard else { return }
        didCreateCard = true
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func complete() {
        markCompleted()
        isActive = false
        onFinish(isFirstRun || didChooseHome ? home : nil, isFirstRun)
    }
}
