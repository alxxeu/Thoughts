import Foundation

/// Пресеты времени бездействия до автоблокировки текущего Space. .never
/// отключает только idle-автоблокировку — ручной Cmd+L продолжает
/// работать в любом случае.
enum AutoLockInterval: Double, CaseIterable, Identifiable {
    case never = 0
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case thirtyMinutes = 1800
    case oneHour = 3600

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .never: return "Only when use \u{2318}+L"
        case .thirtySeconds: return "If away for 30 seconds"
        case .oneMinute: return "If away for 1 minute"
        case .fiveMinutes: return "If away for 5 minutes"
        case .tenMinutes: return "If away for 10 minutes"
        case .thirtyMinutes: return "If away for 30 minutes"
        case .oneHour: return "If away for 1 hour"
        }
    }
}

/// Глобальные настройки Space Lock. Passcode — обязательная база (как в
/// Telegram): включить защиту значит сразу создать 4-значный код. Touch ID
/// — необязательная надстройка поверх него, а не отдельный взаимоисключающий
/// способ — на экране блокировки код-пароль показывается всегда, а кнопка
/// Touch ID появляется только если он включён. Persist через UserDefaults
/// (не секретные значения); сам passcode сюда никогда не попадает — он
/// только в Keychain (см. PasscodeStore).
@Observable
final class SecuritySettings {
    static let shared = SecuritySettings()

    private static let passcodeEnabledKey = "security.isPasscodeEnabled"
    private static let touchIDEnabledKey = "security.isTouchIDEnabled"
    private static let autoLockKey = "security.autoLockInterval"

    /// Мастер-переключатель (как "Passcode Lock" в Telegram): пока
    /// выключен, ни один Space не может быть заблокирован вообще — ни
    /// вручную через Cmd+L, ни через переключатели отдельных Space в
    /// подменю. По умолчанию выключен — Space Lock целиком opt-in.
    var isPasscodeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isPasscodeEnabled, forKey: Self.passcodeEnabledKey)
        }
    }

    /// Осмыслен только пока isPasscodeEnabled == true — самостоятельно
    /// ничего не блокирует и не разблокирует.
    var isTouchIDEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isTouchIDEnabled, forKey: Self.touchIDEnabledKey)
        }
    }

    var autoLockInterval: AutoLockInterval {
        didSet {
            UserDefaults.standard.set(autoLockInterval.rawValue, forKey: Self.autoLockKey)
        }
    }

    private init() {
        isPasscodeEnabled = UserDefaults.standard.bool(forKey: Self.passcodeEnabledKey)
        isTouchIDEnabled = UserDefaults.standard.bool(forKey: Self.touchIDEnabledKey)

        if UserDefaults.standard.object(forKey: Self.autoLockKey) != nil {
            let storedInterval = UserDefaults.standard.double(forKey: Self.autoLockKey)
            autoLockInterval = AutoLockInterval(rawValue: storedInterval) ?? .fiveMinutes
        } else {
            autoLockInterval = .fiveMinutes
        }
    }
}
