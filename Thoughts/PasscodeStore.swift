import Foundation
import Security

/// Хранит 4-значный passcode для Space Lock в Keychain — никогда в
/// UserDefaults/JSON/plaintext. Keychain уже шифрует данные на диске и
/// привязан к учётке пользователя, поэтому хранить сам код (а не хэш)
/// здесь допустимо и проще.
enum PasscodeStore {
    private static let service = "com.alxeu.Thoughts.spacelock"
    private static let account = "space-lock-passcode"

    static var hasPasscode: Bool {
        read() != nil
    }

    /// Возвращает false при неудаче записи в Keychain — вызывающая сторона
    /// не должна считать passcode сохранённым, если это не так (иначе
    /// isPasscodeEnabled=true при фактически несохранённом коде намертво
    /// заблокирует пользователя от собственных карточек).
    @discardableResult
    static func set(_ passcode: String) -> Bool {
        let query = baseQuery()
        SecItemDelete(query as CFDictionary)

        var newItem = query
        newItem[kSecValueData as String] = Data(passcode.utf8)
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(newItem as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func verify(_ passcode: String) -> Bool {
        guard let stored = read() else { return false }
        return stored == passcode
    }

    /// errSecItemNotFound тоже считается успехом — конечное состояние
    /// ("код отсутствует в Keychain"), к которому стремится этот вызов,
    /// уже достигнуто.
    @discardableResult
    static func remove() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
