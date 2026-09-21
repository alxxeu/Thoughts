import Foundation

/// Messages API — https://docs.anthropic.com/en/api/messages
struct AnthropicTextService: AITextService {
    let apiKey: String
    let model: String

    private struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let system: String
        let messages: [Message]
        let max_tokens: Int
    }

    private struct ResponseBody: Decodable {
        struct ContentBlock: Decodable {
            let text: String?
        }
        let content: [ContentBlock]
    }

    private struct ErrorBody: Decodable {
        struct APIError: Decodable {
            let message: String
        }
        let error: APIError
    }

    func generate(systemPrompt: String, userText: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: model,
            system: systemPrompt,
            messages: [.init(role: "user", content: userText)],
            max_tokens: 2048
        ))

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if let errorBody = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                throw AITextServiceError.apiError(errorBody.error.message)
            }
            throw AITextServiceError.invalidResponse
        }

        guard let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data),
              let text = decoded.content.compactMap(\.text).first else {
            throw AITextServiceError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
