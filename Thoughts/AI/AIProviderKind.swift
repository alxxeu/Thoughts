import Foundation

/// Провайдеры AI. Apple Intelligence — на устройстве; Anthropic — свой
/// Messages API; остальные говорят на OpenAI-совместимом Chat Completions
/// (см. OpenAITextService), различаются адресом, ключом и моделью.
enum AIProviderKind: String, CaseIterable, Identifiable, Codable {
    // Порядок case'ов = порядок строк в Provider-пикере (Settings → AI).
    case appleIntelligence
    case openAI
    case anthropic
    case gemini
    case openRouter
    case groq
    case mistral
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        case .groq: return "Groq"
        case .mistral: return "Mistral"
        case .ollama: return "Ollama"
        }
    }

    /// Короткая подпись в переключателе панелей Ask AI.
    var shortName: String {
        switch self {
        case .appleIntelligence: return "Apple"
        case .gemini: return "Gemini"
        default: return displayName
        }
    }

    /// Нужен ли API-ключ. Apple Intelligence работает на устройстве, Ollama —
    /// локальный сервер на этом Mac.
    var needsAPIKey: Bool {
        switch self {
        case .appleIntelligence, .ollama: return false
        default: return true
        }
    }

    /// Провайдеры, у которых в листе ключей есть строка (ключ и/или модель).
    static var configurable: [AIProviderKind] {
        allCases.filter { $0 != .appleIntelligence }
    }

    /// Разумное значение по умолчанию для поля модели — пользователь может
    /// вписать своё. У Apple Intelligence выбора модели нет (одна on-device модель).
    var defaultModel: String {
        switch self {
        case .appleIntelligence: return "on-device"
        case .openAI: return "gpt-4o"
        case .anthropic: return "claude-sonnet-5"
        case .gemini: return "gemini-2.5-flash"
        case .openRouter: return "openai/gpt-4o"
        case .groq: return "llama-3.3-70b-versatile"
        case .mistral: return "mistral-large-latest"
        case .ollama: return "llama3.2"
        }
    }

    /// Адрес Chat Completions для OpenAI-совместимых провайдеров.
    var chatCompletionsURL: URL? {
        switch self {
        case .openAI: return URL(string: "https://api.openai.com/v1/chat/completions")
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")
        case .groq: return URL(string: "https://api.groq.com/openai/v1/chat/completions")
        case .mistral: return URL(string: "https://api.mistral.ai/v1/chat/completions")
        // IP, а не localhost: на IP-адреса ATS не распространяется, http можно.
        case .ollama: return URL(string: "http://127.0.0.1:11434/v1/chat/completions")
        case .appleIntelligence, .anthropic: return nil
        }
    }

    /// Где взять ключ (у Ollama — где скачать сам сервер).
    var apiKeyHelpURL: URL? {
        switch self {
        case .appleIntelligence: return nil
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .openRouter: return URL(string: "https://openrouter.ai/keys")
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
        case .ollama: return URL(string: "https://ollama.com/download")
        }
    }
}
