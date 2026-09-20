import Foundation

/// Какой AI-провайдер сейчас активен. ChatGPT/Claude показываются здесь
/// только как визуальный тизер Pro-подписки — реальная BYOK-инфраструктура
/// (Keychain-хранилище ключей, HTTP-клиенты) остаётся исключительно на
/// ветке feature/pro-subscription; на этой сборке для них нет ни ключей,
/// ни сетевых вызовов, только метаданные для отображения в UI (см.
/// AISettings.hasKey(for:) — всегда false для обоих).
enum AIProviderKind: String, CaseIterable, Identifiable, Codable {
    // Порядок case'ов = порядок строк в Provider-пикере (Settings → AI).
    case appleIntelligence
    case openAI
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .openAI: return "ChatGPT"
        case .anthropic: return "Claude"
        }
    }

    /// У Apple Intelligence выбора модели нет вообще (одна on-device
    /// модель). ChatGPT/Claude — значения только для визуального тизера,
    /// в этой сборке никогда не используются для реального запроса.
    var defaultModel: String {
        switch self {
        case .appleIntelligence: return "on-device"
        case .openAI: return "gpt-4o"
        case .anthropic: return "claude-3-5-sonnet-latest"
        }
    }

    /// Apple Intelligence работает on-device через FoundationModels, ключ
    /// не нужен вообще — её "настроенность" определяется доступностью на
    /// Mac (см. AppleIntelligenceAvailability), а не Keychain.
    var requiresAPIKey: Bool {
        switch self {
        case .appleIntelligence: return false
        case .openAI, .anthropic: return true
        }
    }

    var apiKeyHelpURL: URL? {
        switch self {
        case .appleIntelligence: return nil
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        }
    }
}
