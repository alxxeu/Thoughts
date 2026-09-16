import Foundation

enum AITextServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key configured. Add one in Settings → AI."
        case .invalidResponse:
            return "The AI provider returned an unexpected response."
        case .apiError(let message):
            return message
        }
    }
}

/// Общий интерфейс для любого провайдера (ChatGPT/Claude) — карточка/меню
/// действий не знает, с кем конкретно говорит.
protocol AITextService {
    /// - Parameters:
    ///   - systemPrompt: инструкция про роль/формат ответа (без самого текста карточки).
    ///   - userText: содержимое карточки (или его часть), над которым выполняется действие.
    func generate(systemPrompt: String, userText: String) async throws -> String
}

/// Возвращает сервис для текущего выбранного в Settings провайдера,
/// используя сохранённые в Keychain ключ и модель.
enum AITextServiceFactory {
    static func makeActiveService() throws -> AITextService {
        let settings = AISettings.shared
        let provider = settings.selectedProvider
        guard let apiKey = settings.apiKey(for: provider), !apiKey.isEmpty else {
            throw AITextServiceError.missingAPIKey
        }
        let model = settings.model(for: provider)
        switch provider {
        case .openAI:
            return OpenAITextService(apiKey: apiKey, model: model)
        case .anthropic:
            return AnthropicTextService(apiKey: apiKey, model: model)
        }
    }
}
