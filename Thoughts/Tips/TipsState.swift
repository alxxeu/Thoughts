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
    private static let pendingKey = "tips.pending"
    private static let cooldownStartKey = "tips.cooldownStart"
    /// Следующая плашка — не раньше чем через 3 минуты после того, как
    /// выполнили действие из прошлой (или закрыли её «Got it»).
    static let cooldown: TimeInterval = 180

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
    /// Последняя показанная плашка, действие из которой ещё не выполнили.
    /// Пока она есть — новых плашек нет (приложение не закрывают днями, так что
    /// «одна за запуск» не годится).
    @ObservationIgnored private var pending: Tip?
    /// Когда выполнили действие из прошлой плашки (или закрыли её) — от этого
    /// момента отсчитывается пауза до следующей.
    @ObservationIgnored private var cooldownStart: Date?
    /// Проверка «тур пройден» и часы (в тестах — свои).
    @ObservationIgnored var hasCompletedTour: () -> Bool = { OnboardingState.hasCompletedTour }
    @ObservationIgnored var now: () -> Date = { Date() }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        seen = Set((defaults.stringArray(forKey: Self.seenKey) ?? []).compactMap(Tip.init(rawValue:)))
        spaceCardSlots = Set((defaults.array(forKey: Self.spaceCardsKey) as? [Int]) ?? [])
        pending = defaults.string(forKey: Self.pendingKey).flatMap(Tip.init(rawValue:))
        cooldownStart = defaults.object(forKey: Self.cooldownStartKey) as? Date
    }

    func shouldShow(_ tip: Tip) -> Bool {
        isEnabled && hasCompletedTour() && !seen.contains(tip)
    }

    func markSeen(_ tip: Tip) {
        seen.insert(tip)
        defaults.set(seen.map(\.rawValue).sorted(), forKey: Self.seenKey)
    }

    /// Можно ли сейчас показать новую плашку: на экране ничего нет, действие из
    /// прошлой выполнено (или её закрыли) и прошло 3 минуты.
    var isReadyForToast: Bool {
        guard currentToast == nil, pending == nil else { return false }
        guard let cooldownStart else { return true }
        return now().timeIntervalSince(cooldownStart) >= Self.cooldown
    }

    /// Плашка внизу: если её ещё не показывали и пауза после прошлой прошла.
    func offer(_ tip: Tip) {
        guard shouldShow(tip), isReadyForToast else { return }
        markSeen(tip)
        pending = tip
        defaults.set(tip.rawValue, forKey: Self.pendingKey)
        currentToast = tip
    }

    /// Пользователь сделал то, о чём была плашка: она закрывается, пауза пошла.
    func noteAction(for tip: Tip) {
        guard pending == tip else { return }
        finishPending()
    }

    /// «Got it» — тоже считаем выполненным, иначе плашки встали бы навсегда.
    func dismissToast() { finishPending() }

    private func finishPending() {
        currentToast = nil
        pending = nil
        cooldownStart = now()
        defaults.removeObject(forKey: Self.pendingKey)
        defaults.set(cooldownStart, forKey: Self.cooldownStartKey)
    }

    func markSpaceCard(_ slot: Int) {
        spaceCardSlots.insert(slot)
        defaults.set(spaceCardSlots.sorted(), forKey: Self.spaceCardsKey)
    }

    /// Settings → General → Reset Tips: подсказки и карточки-советы — заново.
    func reset() {
        seen = []
        spaceCardSlots = []
        currentToast = nil
        pending = nil
        cooldownStart = nil
        defaults.removeObject(forKey: Self.seenKey)
        defaults.removeObject(forKey: Self.spaceCardsKey)
        defaults.removeObject(forKey: Self.pendingKey)
        defaults.removeObject(forKey: Self.cooldownStartKey)
    }
}
