import Foundation

/// Опциональный режим, в котором окно Thoughts сидит поверх рабочего стола
/// (чуть выше иконок, ниже обычных окон приложений) — см. план в
/// buzzing-squishing-wombat.md. Persist через UserDefaults, тот же стиль
/// ключей, что в AppearanceSettings.
@Observable
final class DesktopOverlaySettings {
    static let shared = DesktopOverlaySettings()

    private static let isEnabledKey = "desktopOverlay.isEnabled"

    /// Включает саму возможность в Settings. Пока false — окно ведёт себя
    /// ровно как обычно, ничего из нижеперечисленного не применяется.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.isEnabledKey)
        }
    }

    /// Desktop mode — однонаправленное действие (⌥D входит, ⌥1–9 выходит),
    /// не тумблер. Runtime-only: при каждом запуске приложения стартует
    /// false, даже если isEnabled персистентно true.
    var isDesktopModeActive: Bool = false

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.isEnabledKey)
    }
}
