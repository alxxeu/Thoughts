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
    /// File → Clear Space — просит ContentView показать подтверждение
    /// перед необратимым удалением всех карточек активного Space. Само
    /// удаление происходит только после явного подтверждения в алерте,
    /// не по этому уведомлению напрямую.
    static let requestClearSpace = Notification.Name("RequestClearSpace")
    /// Клик по пустому холсту или начало драга по нему — карточки снимают
    /// текстовое выделение/фокус, если он был у одной из них.
    static let clearTextSelection = Notification.Name("ClearTextSelection")
    /// Только что созданная карточка домаунтилась — просит её собственный
    /// CardTextView взять фокус (см. задержку в ContentView.addCard-flow).
    static let focusNewCard = Notification.Name("FocusNewCard")

    // MARK: - Onboarding-гейты (см. OnboardingViewModel.handle) — сигналят
    // о РЕАЛЬНОМ завершении жеста (не о начале), чтобы шаг интерактивного
    // тура продвигался только на настоящее действие пользователя, а не на
    // уже существующее состояние карточки (важно для Replay Onboarding на
    // непустом Space).

    /// CardView.moveGesture.onEnded — карточку реально подвинули (не просто
    /// кликнули по ней).
    static let cardWasMoved = Notification.Name("CardWasMoved")
    /// CardView.resizeGesture.onEnded — карточку реально изменили в размере.
    static let cardWasResized = Notification.Name("CardWasResized")
    /// TagPopoverView — выбран настоящий цвет тега (не "без тега").
    static let cardTagColorWasSet = Notification.Name("CardTagColorWasSet")
    /// TagPopoverView — privacyMode переключился ИМЕННО в .spoiler (не обратно в .none).
    static let cardDidBecomeSpoiler = Notification.Name("CardDidBecomeSpoiler")
}
