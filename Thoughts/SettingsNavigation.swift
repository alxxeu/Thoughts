import AppKit

/// Выбранная вкладка Settings — чтобы открыть окно настроек сразу на нужной
/// вкладке из любого места приложения (напр. "AI Settings…" в панелях Ask AI).
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()

    enum Tab: Hashable {
        case general, appearance, security, shortcuts, ai, about
    }

    var selectedTab: Tab = .general

    private init() {}

    func open(_ tab: Tab) {
        selectedTab = tab
        NSApp.activate(ignoringOtherApps: true)
        // Штатный селектор пункта "Settings…" SwiftUI-сцены Settings.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
