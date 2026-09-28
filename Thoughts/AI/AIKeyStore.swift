import Foundation
import Security

/// Хранит API-ключи ChatGPT/Claude в Keychain — как PasscodeStore для
/// кода блокировки, тот же паттерн (kSecClassGenericPassword), но с
/// отдельным account на каждого провайдера, чтобы оба ключа жили
/// одновременно и не затирали друг друга при переключении.
enum AIKeyStore {
    private static let service = "com.alxeu.Thoughts.aikeys"

    /// При включённом синке с iCloud ключи ещё и в iCloud Keychain (см.
    /// SyncableKeychainItem) — заданный на одном Mac ключ работает на всех.
    static func item(for provider: AIProviderKind) -> SyncableKeychainItem {
        SyncableKeychainItem(service: service, account: provider.rawValue)
    }

    static func key(for provider: AIProviderKind) -> String? {
        item(for: provider).read()
    }

    static func hasKey(for provider: AIProviderKind) -> Bool {
        key(for: provider) != nil
    }

    /// Пустая строка трактуется как удаление — так поле в Settings можно
    /// просто очистить, а не давать отдельную кнопку "Remove".
    @discardableResult
    static func setKey(_ value: String, for provider: AIProviderKind) -> Bool {
        guard !value.isEmpty else { return remove(for: provider) }
        return item(for: provider).write(value)
    }

    @discardableResult
    static func remove(for provider: AIProviderKind) -> Bool {
        item(for: provider).remove()
    }
}
