import Foundation

/// Какой AI-провайдер сейчас активен. BYOK — ключ и модель для КАЖДОГО
/// провайдера хранятся независимо (см. AIKeyStore/AISettings), так что
/// переключение туда-обратно не теряет ранее введённый ключ.
enum AIProviderKind: String, CaseIterable, Identifiable, Codable {
    case openAI
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "ChatGPT"
        case .anthropic: return "Claude"
        }
    }

    /// Разумное значение по умолчанию для поля модели — пользователь может
    /// вписать своё, если у него есть доступ к другой модели.
    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o"
        case .anthropic: return "claude-sonnet-5"
        }
    }

    var apiKeyHelpURL: URL {
        switch self {
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")!
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        }
    }
}
