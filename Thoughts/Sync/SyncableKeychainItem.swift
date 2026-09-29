import Foundation
import Security

/// Строка в Keychain (passcode Space Lock, API-ключ), которая при
/// включённом синке с iCloud живёт ещё и в iCloud Keychain — там она
/// шифруется end-to-end и доезжает до других Mac пользователя.
///
/// Локальная копия (`ThisDeviceOnly`, как было всегда) есть всегда и
/// обновляется при каждой записи: выключение синка не должно ничего отнимать
/// у этого Mac. Synchronizable-копия при выключении синка НЕ удаляется —
/// её удаление стёрло бы значение и на всех остальных Mac.
///
/// Если iCloud Keychain недоступен (выключен в системе, сборка без нужных
/// прав), synchronizable-операции просто не проходят и всё работает на
/// локальной копии.
struct SyncableKeychainItem {
    let service: String
    let account: String

    private var isSyncEnabled: Bool { CloudSyncSettings.shared.isEnabled }

    // MARK: - Public

    func read() -> String? {
        if isSyncEnabled, let synced = read(synchronizable: true) {
            return synced
        }
        return read(synchronizable: false)
    }

    /// Результат — только по локальной копии: она обязательна, iCloud —
    /// по возможности.
    @discardableResult
    func write(_ value: String) -> Bool {
        let stored = write(value, synchronizable: false)
        if isSyncEnabled {
            write(value, synchronizable: true)
        }
        return stored
    }

    @discardableResult
    func remove() -> Bool {
        let removed = remove(synchronizable: false)
        if isSyncEnabled {
            remove(synchronizable: true)
        }
        return removed
    }

    enum Reconciliation: Equatable {
        case nothing
        case uploaded
        /// Взяли значение из iCloud; `replacedDifferentValue` — на этом Mac
        /// было другое (например, другой passcode) и оно заменено.
        case adoptedFromICloud(replacedDifferentValue: Bool)
    }

    /// При включении синка: если в iCloud Keychain уже есть значение (с
    /// другого Mac) — оно побеждает и копируется локально; иначе локальное
    /// выгружается в iCloud.
    @discardableResult
    func reconcile() -> Reconciliation {
        let local = read(synchronizable: false)
        if let synced = read(synchronizable: true) {
            guard synced != local else { return .nothing }
            write(synced, synchronizable: false)
            return .adoptedFromICloud(replacedDifferentValue: local != nil)
        }
        guard let local else { return .nothing }
        return write(local, synchronizable: true) ? .uploaded : .nothing
    }

    // MARK: - Keychain

    private func baseQuery(synchronizable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if synchronizable {
            // iCloud Keychain живёт только в data protection keychain.
            query[kSecUseDataProtectionKeychain as String] = true
            query[kSecAttrSynchronizable as String] = true
        }
        return query
    }

    private func read(synchronizable: Bool) -> String? {
        var query = baseQuery(synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private func write(_ value: String, synchronizable: Bool) -> Bool {
        let query = baseQuery(synchronizable: synchronizable)
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        // Synchronizable-элементы не могут быть ThisDeviceOnly по определению.
        item[kSecAttrAccessible as String] = synchronizable
            ? kSecAttrAccessibleAfterFirstUnlock
            : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if synchronizable && status != errSecSuccess {
            print("iCloud Keychain write failed for \(service)/\(account): \(status)")
        }
        return status == errSecSuccess
    }

    @discardableResult
    private func remove(synchronizable: Bool) -> Bool {
        let status = SecItemDelete(baseQuery(synchronizable: synchronizable) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
