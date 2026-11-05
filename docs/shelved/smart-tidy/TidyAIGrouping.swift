import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Группировка карточек по смыслу для Tidy через Apple Intelligence (on-device).
/// Модель только решает, что с чем связано и в каком порядке; позиции считает
/// `TidyLayout`. Любая ошибка, тайм-аут или неподходящий ответ — nil, и Tidy
/// работает как обычно. NLEmbedding не годится: для русского векторов нет, для
/// английского близость почти не отличает связанное от несвязанного.
enum TidyAIGrouping {
    /// Окно on-device модели ~4096 токенов: ~150 символов на карточку, не больше 40 карточек.
    private static let maxCards = 40
    private static let maxChars = 150
    private static let timeout: Duration = .seconds(20)

    /// nil — умный режим выключен/недоступен или модель не справилась.
    /// spoiler/lock и пустые карточки в модель не уходят.
    static func groups(for cards: [Card]) async -> [[UUID]]? {
        guard AISettings.shared.isEnabled, AISettings.shared.isSmartTidyEnabled,
              AppleIntelligenceAvailability.isAvailable else { return nil }
        let sendable = cards.filter { $0.privacyMode == .none && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard sendable.count >= 3, sendable.count <= maxCards else { return nil }
        guard #available(macOS 26.0, *) else { return nil }
        return await ask(sendable)
    }

    @available(macOS 26.0, *)
    @Generable
    fileprivate struct Grouping {
        @Guide(description: "Groups of related cards. Every card number appears in exactly one group; unrelated cards form their own group.")
        var groups: [Group]
    }

    @available(macOS 26.0, *)
    @Generable
    fileprivate struct Group {
        @Guide(description: "Card numbers of one group, in a sensible reading order (steps, priority, chronology).")
        var cards: [Int]
    }

    @available(macOS 26.0, *)
    private static func ask(_ cards: [Card]) async -> [[UUID]]? {
        let lines = cards.enumerated().map { index, card in
            let text = card.text.replacingOccurrences(of: "\n", with: " ").prefix(maxChars)
            return "\(index)\(card.tagColor.map { " [\($0.rawValue)]" } ?? ""): \(text)"
        }.joined(separator: "\n")
        let instructions = "You organize short notes on a board. Group notes that belong together by topic or purpose. A color tag in brackets is a hint that notes belong together. Reply only with the groups; do not rewrite or invent notes."

        let result: Grouping? = await withTaskGroup(of: Grouping?.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: instructions)
                return try? await session.respond(to: lines, generating: Grouping.self).content
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let result else { return nil }
        let groups = result.groups.map { $0.cards.compactMap { cards.indices.contains($0) ? cards[$0].id : nil } }.filter { !$0.isEmpty }
        // Одна группа или «каждая сама по себе» — разбиения нет, пусть работает обычная логика.
        guard groups.count >= 2, groups.count < cards.count else { return nil }
        return groups
    }
}
