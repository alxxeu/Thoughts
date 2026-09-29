import SwiftUI

/// Открывает окно Settings сразу на нужной вкладке из любого места
/// приложения (напр. "AI Settings…" в панелях Ask AI).
///
/// Открывает через SwiftUI-действие openSettings: старый селектор
/// `showSettingsWindow:` на macOS 14+ для сцены Settings больше не
/// срабатывает. Действие берётся из главного окна (ContentView кладёт его
/// сюда при появлении) — в popover, который живёт в своём
/// NSHostingController вне сцены, собственного openSettings нет.
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()

    enum Tab: Hashable {
        case general, appearance, security, shortcuts, ai, about
    }

    var selectedTab: Tab = .general
    @ObservationIgnored var openSettingsAction: OpenSettingsAction?

    private init() {}

    func open(_ tab: Tab) {
        selectedTab = tab
        NSApp.activate(ignoringOtherApps: true)
        openSettingsAction?()
    }
}
