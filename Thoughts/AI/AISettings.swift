import Foundation

/// Настройки AI-фич: провайдер (в этой сборке всегда Apple Intelligence —
/// BYOK для ChatGPT/Claude остаётся Pro-эксклюзивом) и клавиша отправки в
/// панели Ask AI. selectedProvider сохранён как концепция (не просто
/// константа) ради структурной совместимости с feature/pro-subscription —
/// см. комментарий в AIProviderKind.
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
    }

    func model(for provider: AIProviderKind) -> String {
        provider.defaultModel
    }

    /// Apple Intelligence не хранит ключей — вместо этого проверяется,
    /// доступна ли она вообще на этом Mac (см. AppleIntelligenceAvailability).
    func hasKey(for provider: AIProviderKind) -> Bool {
        AppleIntelligenceAvailability.isAvailable
    }

    /// Настроен ли активный провайдер — им гейтится включение AI-действий
    /// на карточках.
    var isActiveProviderConfigured: Bool {
        hasKey(for: selectedProvider)
    }
}
