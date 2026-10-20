import Foundation
import Observation

/// Подсказки по ходу работы (слой 2 обучения): каждая — один раз, в момент
/// первого использования. Не во время онбординга.
enum Tip: String, CaseIterable {
    /// Цепочка в меню тега: цвета → Spoiler/Lock карточки.
    case tagColors
    /// Перенос/ресайз и создание карточки учит онбординг — отдельной подсказки нет.
    case spaceSwitch, spaceLock, focusMode, askAI
}

/// Что из обучения уже показано — UserDefaults (у каждого Mac своё).
@Observable
final class TipsState {
    static let shared = TipsState()

    private static let enabledKey = "tips.enabled"
    private static let seenKey = "tips.seen"
    private static let spaceCardsKey = "tips.spaceCards"

    @ObservationIgnored private let defaults: UserDefaults

    /// Settings → General → Show Tips.
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }
    private(set) var seen: Set<Tip>
    /// Слоты, в которых уже появлялась карточка-совет (слой 3).
    private(set) var spaceCardSlots: Set<Int>

    /// Подсказка-плашка внизу доски, которая сейчас на экране.
    var currentToast: Tip?
    /// Плашек не больше одной за запуск — чтобы не надоедать.
    @ObservationIgnored private var didShowToastThisSession = false
    /// Проверка «тур пройден» (в тестах — своя).
    @ObservationIgnored var hasCompletedTour: () -> Bool = { OnboardingState.hasCompletedTour }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        seen = Set((defaults.stringArray(forKey: Self.seenKey) ?? []).compactMap(Tip.init(rawValue:)))
        spaceCardSlots = Set((defaults.array(forKey: Self.spaceCardsKey) as? [Int]) ?? [])
    }

    func shouldShow(_ tip: Tip) -> Bool {
        isEnabled && hasCompletedTour() && !seen.contains(tip)
    }

    func markSeen(_ tip: Tip) {
        seen.insert(tip)
        defaults.set(seen.map(\.rawValue).sorted(), forKey: Self.seenKey)
    }

    /// Плашка внизу: показывается, если её ещё не было и в этот запуск плашек не было.
    func offer(_ tip: Tip) {
        guard shouldShow(tip), currentToast == nil, !didShowToastThisSession else { return }
        didShowToastThisSession = true
        markSeen(tip)
        currentToast = tip
    }

    func dismissToast() { currentToast = nil }

    func markSpaceCard(_ slot: Int) {
        spaceCardSlots.insert(slot)
        defaults.set(spaceCardSlots.sorted(), forKey: Self.spaceCardsKey)
    }

    /// Settings → General → Reset Tips: подсказки и карточки-советы — заново.
    func reset() {
        seen = []
        spaceCardSlots = []
        didShowToastThisSession = false
        defaults.removeObject(forKey: Self.seenKey)
        defaults.removeObject(forKey: Self.spaceCardsKey)
    }
}
