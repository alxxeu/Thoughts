import Foundation

/// BYOK-настройки AI-фич: включён ли AI вообще, какой провайдер активен,
/// какая модель у каждого из них, и есть ли уже сохранённый ключ. Сами ключи
/// в Keychain (AIKeyStore), не здесь — но признак "ключ есть/нет" зеркалируется
/// в @Observable-свойство, иначе SwiftUI не увидит изменение (Keychain не
/// наблюдаем сам по себе).
@Observable
final class AISettings {
    static let shared = AISettings()

    private static let enabledKey = "ai.enabled"
    private static let providerKey = "ai.selectedProvider"
    private static let sendKeyBindingKey = "ai.sendKeyBinding"
    private static func modelKey(for provider: AIProviderKind) -> String {
        "ai.model.\(provider.rawValue)"
    }

    /// Disabled в Settings → AI: все входы в Ask AI (капсула, Focus Mode,
    /// контекстное меню текста) скрыты.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    var selectedProvider: AIProviderKind {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: Self.providerKey)
        }
    }

    var sendKeyBinding: AISendKeyBinding {
        didSet {
            UserDefaults.standard.set(sendKeyBinding.rawValue, forKey: Self.sendKeyBindingKey)
        }
    }

    private var models: [AIProviderKind: String]
    private var keyedProviders: Set<AIProviderKind>

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true

        if let raw = UserDefaults.standard.string(forKey: Self.providerKey),
           let value = AIProviderKind(rawValue: raw) {
            selectedProvider = value
        } else {
            selectedProvider = .appleIntelligence
        }

        if let raw = UserDefaults.standard.string(forKey: Self.sendKeyBindingKey),
           let value = AISendKeyBinding(rawValue: raw) {
            sendKeyBinding = value
        } else {
            sendKeyBinding = .returnSends
        }

        models = Dictionary(uniqueKeysWithValues: AIProviderKind.allCases.map {
            ($0, UserDefaults.standard.string(forKey: Self.modelKey(for: $0)) ?? $0.defaultModel)
        })
        keyedProviders = Self.readKeyedProviders()
    }

    func model(for provider: AIProviderKind) -> String {
        models[provider] ?? provider.defaultModel
    }

    func setModel(_ value: String, for provider: AIProviderKind) {
        models[provider] = value
        UserDefaults.standard.set(value, forKey: Self.modelKey(for: provider))
    }

    /// "Можно ли прямо сейчас выбрать этого провайдера" — этим гейтится
    /// строка в Picker. Для провайдеров с ключом — есть ли сохранённый в
    /// Keychain ключ; для Apple Intelligence — доступна ли она на этом Mac;
    /// Ollama ключа не требует (работает ли сервер, видно по ответу).
    func hasKey(for provider: AIProviderKind) -> Bool {
        switch provider {
        case .appleIntelligence: return AppleIntelligenceAvailability.isAvailable
        case .ollama: return true
        default: return keyedProviders.contains(provider)
        }
    }

    /// Перечитать наличие ключей — после того как синк с iCloud принёс
    /// ключи с другого Mac (см. KeychainSync).
    func refreshKeyState() {
        keyedProviders = Self.readKeyedProviders()
    }

    func apiKey(for provider: AIProviderKind) -> String? {
        AIKeyStore.key(for: provider)
    }

    func setAPIKey(_ value: String, for provider: AIProviderKind) {
        guard provider.needsAPIKey else { return }
        AIKeyStore.setKey(value, for: provider)
        if AIKeyStore.hasKey(for: provider) {
            keyedProviders.insert(provider)
        } else {
            keyedProviders.remove(provider)
        }
    }

    private static func readKeyedProviders() -> Set<AIProviderKind> {
        Set(AIProviderKind.allCases.filter { $0.needsAPIKey && AIKeyStore.hasKey(for: $0) })
    }
}
