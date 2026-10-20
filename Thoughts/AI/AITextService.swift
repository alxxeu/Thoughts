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
        guard settings.isEnabled else {
            throw AITextServiceError.apiError("AI is turned off. Choose a provider in Settings \u{2192} AI.")
        }
        let provider = settings.selectedProvider
        switch provider {
        case .openAI, .gemini, .openRouter, .groq, .mistral:
            guard let apiKey = settings.apiKey(for: provider), !apiKey.isEmpty,
                  let endpoint = provider.chatCompletionsURL else {
                throw AITextServiceError.missingAPIKey
            }
            return OpenAITextService(endpoint: endpoint, apiKey: apiKey, model: settings.model(for: provider))
        case .ollama:
            guard let endpoint = provider.chatCompletionsURL else { throw AITextServiceError.invalidResponse }
            return OpenAITextService(endpoint: endpoint, apiKey: nil, model: settings.model(for: provider))
        case .anthropic:
            guard let apiKey = settings.apiKey(for: provider), !apiKey.isEmpty else {
                throw AITextServiceError.missingAPIKey
            }
            return AnthropicTextService(apiKey: apiKey, model: settings.model(for: provider))
        case .appleIntelligence:
            guard #available(macOS 26.0, *), AppleIntelligenceAvailability.isAvailable else {
                throw AITextServiceError.apiError(
                    AppleIntelligenceAvailability.unavailableReasonDescription ?? "Apple Intelligence is unavailable."
                )
            }
            return AppleIntelligenceTextService()
        }
    }

    /// Единая сборка запроса для всех панелей Ask AI: контекст (заметка,
    /// выделение или весь Space) с подписью, затем сам вопрос.
    static func ask(
        _ question: String,
        context: String,
        contextLabel: String,
        questionLabel: String = "Request",
        systemPrompt: String
    ) async throws -> String {
        let service = try makeActiveService()
        let userText = context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? question
            : "\(contextLabel):\n\(context)\n\n\(questionLabel): \(question)"
        let answer = try await service.generate(systemPrompt: systemPrompt, userText: userText)
        // Чек-листы — в стандартный `- [ ] `, как при наборе в карточке.
        return MarkdownFormatting.standardizingTaskMarkers(answer, atLineStart: true)
    }
}
