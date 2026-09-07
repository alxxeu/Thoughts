@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers
import Foundation

/// Снимок карточки для передачи в CoreSpotlight — простой Sendable-слепок,
/// а не сама @Observable-модель, чтобы индексация могла безопасно уйти
/// на фоновый поток внутри completion handler'ов CSSearchableIndex.
struct SpotlightCardSnapshot: Sendable {
    let id: UUID
    let text: String
    let privacyMode: CardPrivacyMode
    let workspaceName: String
}

/// nonisolated целиком: CSSearchableIndex доставляет свои completion
/// handler'ы на произвольную (не главную) очередь, а этот тип работает
/// только со Sendable-слепками, так что MainActor-изоляция ему не нужна и
/// только заставляла бы прыгать между потоками без всякой пользы.
nonisolated enum SpotlightIndexer {
    private static let domainIdentifier = "com.alxeu.Thoughts.cards"
    private static let identifierPrefix = "card-"

    static func identifier(for cardID: UUID) -> String {
        identifierPrefix + cardID.uuidString
    }

    static func cardID(from identifier: String) -> UUID? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(identifierPrefix.count)))
    }

    /// Полностью перестраивает индекс на каждое сохранение борда. Карточек
    /// у пользователя мало (личный борд, максимум 9 спэйсов), поэтому
    /// diff-логика (отдельно add/remove/update) только усложнила бы код
    /// ради незаметной экономии — проще снести и построить заново.
    static func reindexAll(_ cards: [SpotlightCardSnapshot]) {
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in
            let items = cards.compactMap(searchableItem(for:))
            guard !items.isEmpty else { return }
            index.indexSearchableItems(items)
        }
    }

    private static func searchableItem(for card: SpotlightCardSnapshot) -> CSSearchableItem? {
        // Карточки за спойлером или локом не должны попадать в системный
        // поиск — иначе их содержимое утекает через Spotlight в обход
        // приватности, которую пользователь явно включил.
        guard card.privacyMode == .none else { return nil }

        let content = card.text
            .replacingOccurrences(of: "\u{FFFC}", with: "\n") // плейсхолдер разделителя
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        let firstLine = content
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? content

        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = String(firstLine.prefix(80))
        attributeSet.contentDescription = content
        attributeSet.keywords = [card.workspaceName, "Thoughts"]

        return CSSearchableItem(
            uniqueIdentifier: identifier(for: card.id),
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
    }
}
