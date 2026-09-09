import Foundation

enum AppColorScheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Пользовательский выбор темы (независимо от системной Light/Dark) —
/// применяется через .preferredColorScheme в ThoughtsApp. Persist через
/// UserDefaults, тот же стиль ключей, что в SecuritySettings.
@Observable
final class AppearanceSettings {
    static let shared = AppearanceSettings()

    private static let colorSchemeKey = "appearance.colorScheme"

    var colorScheme: AppColorScheme {
        didSet {
            UserDefaults.standard.set(colorScheme.rawValue, forKey: Self.colorSchemeKey)
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.colorSchemeKey),
           let value = AppColorScheme(rawValue: raw) {
            colorScheme = value
        } else {
            colorScheme = .system
        }
    }
}
