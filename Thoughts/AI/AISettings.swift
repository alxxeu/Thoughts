import Foundation

/// BYOK-настройки AI-фич: какой провайдер активен, какая модель у
/// каждого из них, и есть ли уже сохранённый ключ. Сами ключи в Keychain
/// (AIKeyStore), не здесь — но признак "ключ есть/нет" зеркалируется в
/// @Observable-свойства, иначе SwiftUI не увидит изменение (Keychain не
/// наблюдаем сам по себе).
@Observable
final class AISettings {
    static let shared = AISettings()

    private static let providerKey = "ai.selectedProvider"
    private static let sendKeyBindingKey = "ai.sendKeyBinding"
    private static func modelKey(for provider: AIProviderKind) -> String {
        "ai.model.\(provider.rawValue)"
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

    var openAIModel: String {
        didSet {
            UserDefaults.standard.set(openAIModel, forKey: Self.modelKey(for: .openAI))
        }
    }

    var anthropicModel: String {
        didSet {
            UserDefaults.standard.set(anthropicModel, forKey: Self.modelKey(for: .anthropic))
        }
    }

    private(set) var hasOpenAIKey: Bool
    private(set) var hasAnthropicKey: Bool

    private init() {
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

        openAIModel = UserDefaults.standard.string(forKey: Self.modelKey(for: .openAI)) ?? AIProviderKind.openAI.defaultModel
        anthropicModel = UserDefaults.standard.string(forKey: Self.modelKey(for: .anthropic)) ?? AIProviderKind.anthropic.defaultModel

        hasOpenAIKey = AIKeyStore.hasKey(for: .openAI)
        hasAnthropicKey = AIKeyStore.hasKey(for: .anthropic)
    }

    func model(for provider: AIProviderKind) -> String {
        switch provider {
        case .openAI: return openAIModel
        case .anthropic: return anthropicModel
        case .appleIntelligence: return provider.defaultModel
        }
    }

    /// Для ChatGPT/Claude — есть ли сохранённый в Keychain ключ. Для
    /// Apple Intelligence ключа не бывает — вместо этого проверяется,
    /// доступна ли она вообще на этом Mac (см. AppleIntelligenceAvailability).
    /// Оба смысла сходятся в одном: "можно ли прямо сейчас выбрать этого
    /// провайдера" — этим гейтится сегмент в Picker.
    func hasKey(for provider: AIProviderKind) -> Bool {
        switch provider {
        case .openAI: return hasOpenAIKey
        case .anthropic: return hasAnthropicKey
        case .appleIntelligence: return AppleIntelligenceAvailability.isAvailable
        }
    }

    func apiKey(for provider: AIProviderKind) -> String? {
        AIKeyStore.key(for: provider)
    }

    func setAPIKey(_ value: String, for provider: AIProviderKind) {
        AIKeyStore.setKey(value, for: provider)
        switch provider {
        case .openAI: hasOpenAIKey = AIKeyStore.hasKey(for: .openAI)
        case .anthropic: hasAnthropicKey = AIKeyStore.hasKey(for: .anthropic)
        case .appleIntelligence: break // Apple Intelligence ключей не хранит, сюда не вызывается
        }
    }

    /// Настроен ли активный (выбранный) провайдер — им гейтится включение
    /// AI-действий на карточках.
    var isActiveProviderConfigured: Bool {
        hasKey(for: selectedProvider)
    }
}
