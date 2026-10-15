import Foundation
import FoundationModels

/// On-device провайдер через Apple Intelligence (FoundationModels,
/// macOS 26+) — бесплатный, без API-ключа и без сети, но заметно слабее
/// ChatGPT/Claude и без выбора модели. Доступность проверяется ДО
/// создания этого сервиса, в AITextServiceFactory — см.
/// AppleIntelligenceAvailability.
@available(macOS 26.0, *)
struct AppleIntelligenceTextService: AITextService {
    static let contextTooLargeMessage = "Apple Intelligence runs on your Mac and can only read about 3,000 words at a time \u{2014} there\u{2019}s more text here than that.\n\nTo ask about bigger Spaces, switch to ChatGPT or Claude with your own API key in Settings \u{2192} AI. Or ask about a single card instead."

    func generate(systemPrompt: String, userText: String) async throws -> String {
        let session = LanguageModelSession(instructions: systemPrompt)
        do {
            let response = try await session.respond(to: userText)
            return response.content
        } catch {
            // Окно on-device модели — ~4096 токенов: большой Space целиком
            // в него не влезает, а системный текст ошибки ничего не объясняет.
            throw AITextServiceError.apiError(
                Self.isContextTooLarge(error) ? Self.contextTooLargeMessage : error.localizedDescription
            )
        }
    }

    /// macOS 27 бросает LanguageModelError, macOS 26 — устаревший GenerationError.
    static func isContextTooLarge(_ error: Error) -> Bool {
        if #available(macOS 27.0, *), case .contextSizeExceeded? = error as? LanguageModelError {
            return true
        }
        if case .exceededContextWindowSize? = error as? LanguageModelSession.GenerationError {
            return true
        }
        return false
    }
}
