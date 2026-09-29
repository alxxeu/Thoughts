import Foundation

/// Плоский value-снимок доски — общий язык для бэкапа (BackupCodec),
/// слияния (BoardMerger) и синка с iCloud: в отличие от @Observable Card,
/// его можно спокойно копировать, сравнивать и кодировать вне главного
/// потока.
struct BoardSnapshot: Codable, Equatable {
    var workspaces: [WorkspaceRecord]
    var cards: [CardRecord]
}

struct WorkspaceRecord: Codable, Equatable {
    var slot: Int
    var name: String
    var isProtected: Bool
    var modifiedAt: Date
}

struct CardRecord: Codable, Equatable {
    var id: UUID
    var workspaceSlot: Int
    var text: String
    var formattingData: Data?
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var raisedAt: Date
    /// Строкой, а не CardTagColor: неизвестный цвет (из более новой версии
    /// приложения) не должен ронять разбор всего бэкапа — просто теряется.
    var tagColor: String?
    var privacyMode: String
    var isAIGenerated: Bool
    var contentModifiedAt: Date
    var geometryModifiedAt: Date
    var metaModifiedAt: Date
}

extension CardRecord {
    init(_ card: Card, slot: Int) {
        id = card.id
        workspaceSlot = slot
        text = card.text
        formattingData = card.formattingData
        x = card.position.x
        y = card.position.y
        width = card.size.width
        height = card.size.height
        raisedAt = card.raisedAt
        tagColor = card.tagColor?.rawValue
        privacyMode = card.privacyMode.rawValue
        isAIGenerated = card.isAIGenerated
        contentModifiedAt = card.contentModifiedAt
        geometryModifiedAt = card.geometryModifiedAt
        metaModifiedAt = card.metaModifiedAt
    }

    /// Переносит поля записи в существующую карточку (сохраняя её
    /// идентичность — открытая CardView не пересоздаётся) или в новую.
    func apply(to card: Card) {
        if card.text != text { card.text = text }
        if card.formattingData != formattingData { card.formattingData = formattingData }
        let position = CGPoint(x: x, y: y)
        if card.position != position { card.position = position }
        let size = CGSize(width: width, height: height)
        if card.size != size { card.size = size }
        card.raisedAt = raisedAt
        let tag = tagColor.flatMap(CardTagColor.init(rawValue:))
        if card.tagColor != tag { card.tagColor = tag }
        // Неизвестный режим приватности — только в сторону большей защиты:
        // лучше лишний раз спросить Touch ID, чем открыть приватное.
        let mode = CardPrivacyMode(rawValue: privacyMode) ?? .lock
        if card.privacyMode != mode { card.privacyMode = mode }
        if card.isAIGenerated != isAIGenerated { card.isAIGenerated = isAIGenerated }
        card.contentModifiedAt = contentModifiedAt
        card.geometryModifiedAt = geometryModifiedAt
        card.metaModifiedAt = metaModifiedAt
    }

    func makeCard() -> Card {
        let card = Card(id: id, position: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
        apply(to: card)
        return card
    }
}

extension WorkspaceRecord {
    init(_ workspace: Workspace) {
        slot = workspace.slot
        name = workspace.name
        isProtected = workspace.isProtected
        modifiedAt = workspace.modifiedAt
    }
}

extension BoardSnapshot {
    /// Сколько защищённого содержимого в снимке — для предупреждений при
    /// экспорте/импорте. Защищённый Space считается, только если в нём
    /// есть карточки: пустой ничего не выдаёт.
    struct LockedSummary {
        var protectedSpaceNames: [String]
        var lockedCardCount: Int

        var isEmpty: Bool { protectedSpaceNames.isEmpty && lockedCardCount == 0 }
    }

    func lockedSummary(passcodeEnabled: Bool) -> LockedSummary {
        let slotsWithCards = Set(cards.map(\.workspaceSlot))
        let protectedSpaces = passcodeEnabled
            ? workspaces.filter { $0.isProtected && slotsWithCards.contains($0.slot) }.sorted { $0.slot < $1.slot }
            : []
        return LockedSummary(
            protectedSpaceNames: protectedSpaces.map(\.name),
            lockedCardCount: cards.filter { $0.privacyMode == CardPrivacyMode.lock.rawValue }.count
        )
    }

    /// Защищённые Spaces с карточками — независимо от того, включён ли
    /// passcode на этом Mac (для проверки при импорте).
    var hasProtectedSpacesWithCards: Bool {
        let slotsWithCards = Set(cards.map(\.workspaceSlot))
        return workspaces.contains { $0.isProtected && slotsWithCards.contains($0.slot) }
    }
}
