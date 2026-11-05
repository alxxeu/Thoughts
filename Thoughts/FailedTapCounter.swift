import Foundation

/// Считает подряд неудачные нажатия на кнопки «зажми» (× карточки, галочка плитки):
/// на третьей подряд `fail` возвращает true — пора показать подсказку «Hold…».
/// Пауза дольше `window` начинает счёт заново.
struct FailedTapCounter {
    var limit = 3
    var window: TimeInterval = 3
    private var count = 0
    private var last: Date?

    mutating func fail(at now: Date = Date()) -> Bool {
        if let last, now.timeIntervalSince(last) > window { count = 0 }
        last = now
        count += 1
        guard count >= limit else { return false }
        reset()
        return true
    }

    mutating func reset() {
        count = 0
        last = nil
    }
}
