import Foundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, security, shortcuts, ai, pro, about
    var id: String { rawValue }
}

/// Позволяет коду вне SettingsView (кнопка Tidy Cards в ContentView,
/// "Learn more" в AISettingsTab) открыть окно Settings сразу на нужном
/// табе. Обычный синглтон-паттерн, как AppearanceSettings/AISettings/
/// DesktopOverlaySettings — просто данные, не событие, поэтому нет гонки
/// со временем открытия окна Settings (в отличие от NotificationCenter).
@Observable
final class SettingsNavigator {
    static let shared = SettingsNavigator()
    var selectedTab: SettingsTab = .general
    private init() {}
}
