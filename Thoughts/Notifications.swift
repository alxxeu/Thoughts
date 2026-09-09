import Foundation

extension Notification.Name {
    static let switchWorkspace = Notification.Name("SwitchWorkspace")
    static let highlightCard = Notification.Name("HighlightCard")
    /// Посылается любой карточкой при начале клика/драга по ней (object —
    /// её UUID). Используется другими карточками, чтобы понять, что клик
    /// произошёл вне их — см. relock-логику в CardView.
    static let cardWasClicked = Notification.Name("CardWasClicked")
    /// Cmd+L — блокирует текущий активный Space (см. ThoughtsApp/ContentView).
    static let lockCurrentSpace = Notification.Name("LockCurrentSpace")
    /// "Replay Onboarding" в Settings → General — показывает тур заново
    /// поверх канвы, не дожидаясь следующего первого запуска.
    static let replayOnboarding = Notification.Name("ReplayOnboarding")
}
