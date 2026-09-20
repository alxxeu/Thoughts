import Foundation

enum AITextServiceError: LocalizedError {
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The AI provider returned an unexpected response."
        case .apiError(let message):
            return message
        }
    }
}

/// Общий интерфейс для любого провайдера — карточка/меню действий не
/// знает, с кем конкретно говорит.
protocol AITextService {
    /// - Parameters:
    ///   - systemPrompt: инструкция про роль/формат ответа (без самого текста карточки).
    ///   - userText: содержимое карточки (или его часть), над которым выполняется действие.
    func generate(systemPrompt: String, userText: String) async throws -> String
}

/// Возвращает сервис для текущего провайдера. ChatGPT/Claude — Pro-тизер
/// (см. AIProviderKind/AISettings) — Picker их выбор не даёт совершить, но
/// явная ветка здесь на случай "застрявшего" значения в UserDefaults
/// (например, после переключения веток на одной машине) — честнее
/// бросить ошибку, чем молча выполнить запрос через Apple Intelligence
/// под видом другого провайдера.
enum AITextServiceFactory {
    static func makeActiveService() throws -> AITextService {
        switch AISettings.shared.selectedProvider {
        case .appleIntelligence:
            guard #available(macOS 26.0, *), AppleIntelligenceAvailability.isAvailable else {
                throw AITextServiceError.apiError(
                    AppleIntelligenceAvailability.unavailableReasonDescription ?? "Apple Intelligence is unavailable."
                )
            }
            return AppleIntelligenceTextService()
        case .openAI, .anthropic:
            throw AITextServiceError.apiError(
                "\(AISettings.shared.selectedProvider.displayName) will be available later in a Pro subscription."
            )
        }
    }
}
