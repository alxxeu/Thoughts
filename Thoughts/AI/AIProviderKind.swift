import Foundation

/// Какой AI-провайдер сейчас активен. BYOK — ключ и модель для КАЖДОГО
/// провайдера хранятся независимо (см. AIKeyStore/AISettings), так что
/// переключение туда-обратно не теряет ранее введённый ключ.
enum AIProviderKind: String, CaseIterable, Identifiable, Codable {
    // Порядок case'ов = порядок строк в Provider-пикере (Settings → AI).
    case appleIntelligence
    case openAI
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "ChatGPT"
        case .anthropic: return "Claude"
        case .appleIntelligence: return "Apple Intelligence"
        }
    }

    /// Разумное значение по умолчанию для поля модели — пользователь может
    /// вписать своё, если у него есть доступ к другой модели. У Apple
    /// Intelligence выбора модели нет вообще (одна on-device модель).
    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o"
        case .anthropic: return "claude-sonnet-5"
        case .appleIntelligence: return "on-device"
        }
    }

    /// ChatGPT/Claude — BYOK, нужен ключ пользователя. Apple Intelligence
    /// работает on-device через FoundationModels, ключ не нужен вообще —
    /// её "настроенность" определяется доступностью на Mac (см.
    /// AppleIntelligenceAvailability), а не Keychain.
    var requiresAPIKey: Bool {
        switch self {
        case .openAI, .anthropic: return true
        case .appleIntelligence: return false
        }
    }

    var apiKeyHelpURL: URL? {
        switch self {
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")!
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .appleIntelligence: return nil
        }
    }
}
