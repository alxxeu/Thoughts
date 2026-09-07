import Foundation

extension Notification.Name {
    static let switchWorkspace = Notification.Name("SwitchWorkspace")
    static let highlightCard = Notification.Name("HighlightCard")
    /// Посылается любой карточкой при начале клика/драга по ней (object —
    /// её UUID). Используется другими карточками, чтобы понять, что клик
    /// произошёл вне их — см. relock-логику в CardView.
    static let cardWasClicked = Notification.Name("CardWasClicked")
}
