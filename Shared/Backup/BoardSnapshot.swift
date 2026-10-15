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
    /// Markdown. Записи старого формата (бэкапы и iCloud со старых версий)
    /// переводятся при чтении — см. init(from:) и RecordMapping.
    var text: String
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

extension CardRecord {
    private enum CodingKeys: String, CodingKey {
        case id, workspaceSlot, text, textFormat, formattingData, x, y, width, height, raisedAt
        case tagColor, privacyMode, isAIGenerated, contentModifiedAt, geometryModifiedAt, metaModifiedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        workspaceSlot = try c.decode(Int.self, forKey: .workspaceSlot)
        let rawText = try c.decode(String.self, forKey: .text)
        let format = try c.decodeIfPresent(Int.self, forKey: .textFormat) ?? MarkdownMigration.legacyFormat
        text = format < MarkdownMigration.markdownFormat
            ? MarkdownMigration.markdown(text: rawText, formattingData: try c.decodeIfPresent(Data.self, forKey: .formattingData))
            : rawText
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
        raisedAt = try c.decode(Date.self, forKey: .raisedAt)
        tagColor = try c.decodeIfPresent(String.self, forKey: .tagColor)
        privacyMode = try c.decode(String.self, forKey: .privacyMode)
        isAIGenerated = try c.decode(Bool.self, forKey: .isAIGenerated)
        contentModifiedAt = try c.decode(Date.self, forKey: .contentModifiedAt)
        geometryModifiedAt = try c.decode(Date.self, forKey: .geometryModifiedAt)
        metaModifiedAt = try c.decode(Date.self, forKey: .metaModifiedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(workspaceSlot, forKey: .workspaceSlot)
        try c.encode(text, forKey: .text)
        try c.encode(MarkdownMigration.markdownFormat, forKey: .textFormat)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(raisedAt, forKey: .raisedAt)
        try c.encodeIfPresent(tagColor, forKey: .tagColor)
        try c.encode(privacyMode, forKey: .privacyMode)
        try c.encode(isAIGenerated, forKey: .isAIGenerated)
        try c.encode(contentModifiedAt, forKey: .contentModifiedAt)
        try c.encode(geometryModifiedAt, forKey: .geometryModifiedAt)
        try c.encode(metaModifiedAt, forKey: .metaModifiedAt)
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
