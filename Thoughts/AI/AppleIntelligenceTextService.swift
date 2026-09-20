import Foundation
import FoundationModels

/// On-device провайдер через Apple Intelligence (FoundationModels,
/// macOS 26+) — бесплатный, без API-ключа и без сети, но заметно слабее
/// ChatGPT/Claude и без выбора модели. Доступность проверяется ДО
/// создания этого сервиса, в AITextServiceFactory — см.
/// AppleIntelligenceAvailability.
@available(macOS 26.0, *)
struct AppleIntelligenceTextService: AITextService {
    func generate(systemPrompt: String, userText: String) async throws -> String {
        let session = LanguageModelSession(instructions: systemPrompt)
        do {
            let response = try await session.respond(to: userText)
            return response.content
        } catch {
            throw AITextServiceError.apiError(error.localizedDescription)
        }
    }
}
