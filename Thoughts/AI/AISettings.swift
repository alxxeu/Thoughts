import Foundation

/// Настройки AI-фич: провайдер и клавиша отправки в панели Ask AI. ChatGPT/
/// Claude показываются в Provider-пикере как тизер Pro-подписки, но
/// реально выбрать их нельзя — hasKey(for:) ниже жёстко возвращает false
/// для обоих (Keychain-хранилища на этой ветке нет), а строки в пикере
/// гасятся через тот же .disabled(!hasKey(...)), что и на Pro-ветке.
@Observable
final class AISettings {
    static let shared = AISettings()

    private static let providerKey = "ai.selectedProvider"
    private static let sendKeyBindingKey = "ai.sendKeyBinding"

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

    private init() {
        // Только .appleIntelligence реально доступен на этой сборке —
        // если в UserDefaults лежит "openAI"/"anthropic" (например, после
        // переключения веток на одной машине), не застреваем на
        // недоступном провайдере молча, откатываемся на рабочий сразу.
        if let raw = UserDefaults.standard.string(forKey: Self.providerKey),
           let value = AIProviderKind(rawValue: raw),
           value == .appleIntelligence {
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
    }

    func model(for provider: AIProviderKind) -> String {
        provider.defaultModel
    }

    /// Apple Intelligence не хранит ключей — вместо этого проверяется,
    /// доступна ли она вообще на этом Mac (см. AppleIntelligenceAvailability).
    /// ChatGPT/Claude — Pro-эксклюзив, на этой сборке нет ни Keychain, ни
    /// сетевых сервисов для них, поэтому всегда false.
    func hasKey(for provider: AIProviderKind) -> Bool {
        switch provider {
        case .appleIntelligence: return AppleIntelligenceAvailability.isAvailable
        case .openAI, .anthropic: return false
        }
    }

    /// Настроен ли активный провайдер — им гейтится включение AI-действий
    /// на карточках.
    var isActiveProviderConfigured: Bool {
        hasKey(for: selectedProvider)
    }
}
