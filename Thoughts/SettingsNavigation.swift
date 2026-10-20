import SwiftUI

/// Открывает окно Settings сразу на нужной вкладке из любого места
/// приложения (напр. "AI Settings…" в панелях Ask AI).
///
/// Settings — обычная сцена Window (как у Thaw), открывается через
/// openWindow(id:). Действие берётся из главного окна (ContentView кладёт
/// его сюда при появлении) — в popover, который живёт в своём
/// NSHostingController вне сцены, собственного openWindow нет.
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    static let windowID = "settings"

    enum Tab: Hashable, CaseIterable {
        case general, appearance, security, shortcuts, ai, plugins, about
    }

    var selectedTab: Tab = .general
    @ObservationIgnored var openWindowAction: OpenWindowAction?

    private init() {}

    func open(_ tab: Tab) {
        selectedTab = tab
        NSApp.activate(ignoringOtherApps: true)
        openWindowAction?(id: Self.windowID)
    }
}
