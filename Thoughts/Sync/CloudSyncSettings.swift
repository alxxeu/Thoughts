import Foundation
import Security

/// Состояние синка с iCloud для UI (Settings → General → iCloud).
enum CloudSyncStatus: Equatable {
    case off
    /// Синк включён, но iCloud сейчас недоступен (нет аккаунта, выход из
    /// аккаунта, ограничения) — локальные данные при этом не трогаются.
    case unavailable(String)
    case syncing
    case upToDate(Date)
    case failed(String)
}

/// Настройка "Sync with iCloud" и текущий статус. Сам синк — CloudSyncEngine.
@Observable
final class CloudSyncSettings {
    static let shared = CloudSyncSettings()

    private static let isEnabledKey = "sync.isEnabled"

    /// Включён пользователем. Меняется только через CloudSyncEngine.enable /
    /// disable — там же первое включение, сброс состояния и т.п.
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.isEnabledKey) }
    }

    var status: CloudSyncStatus = .off

    /// Есть ли у сборки iCloud-entitlement. Без него (тестовые копии,
    /// сборка без capability) CKContainer падает при создании — синк
    /// просто недоступен.
    let isAvailableInBuild: Bool = CloudSyncSettings.hasCloudKitEntitlement()

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.isEnabledKey)
    }

    private static func hasCloudKitEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let services = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil)
        let containers = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil)
        let hasCloudKit = (services as? [String])?.contains("CloudKit") ?? false
        let hasContainer = (containers as? [String])?.contains(RecordMapping.containerIdentifier) ?? false
        return hasCloudKit && hasContainer
    }
}
