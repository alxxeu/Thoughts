import Foundation
import Security

/// Хранит API-ключи ChatGPT/Claude в Keychain — как PasscodeStore для
/// кода блокировки, тот же паттерн (kSecClassGenericPassword), но с
/// отдельным account на каждого провайдера, чтобы оба ключа жили
/// одновременно и не затирали друг друга при переключении.
enum AIKeyStore {
    private static let service = "com.alxeu.Thoughts.aikeys"

    static func key(for provider: AIProviderKind) -> String? {
        read(account: provider.rawValue)
    }

    static func hasKey(for provider: AIProviderKind) -> Bool {
        key(for: provider) != nil
    }

    /// Пустая строка трактуется как удаление — так поле в Settings можно
    /// просто очистить, а не давать отдельную кнопку "Remove".
    @discardableResult
    static func setKey(_ value: String, for provider: AIProviderKind) -> Bool {
        guard !value.isEmpty else { return remove(for: provider) }

        let query = baseQuery(account: provider.rawValue)
        SecItemDelete(query as CFDictionary)

        var newItem = query
        newItem[kSecValueData as String] = Data(value.utf8)
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(newItem as CFDictionary, nil)
        return status == errSecSuccess
    }

    @discardableResult
    static func remove(for provider: AIProviderKind) -> Bool {
        let status = SecItemDelete(baseQuery(account: provider.rawValue) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
