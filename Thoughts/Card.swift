import SwiftUI

enum CardPrivacyMode: String, Codable {
    case none
    case spoiler
    case lock
}

enum CardTagColor: String, CaseIterable, Codable, Identifiable {
    case red, orange, yellow, green, blue, indigo, purple
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        }
    }
}

@Observable
final class Card: Identifiable, Codable {
    let id: UUID
    var position: CGPoint
    var size: CGSize
    var text: String = ""
    /// Форматирование (bold и т.п.) — сериализованный NSAttributedString
    /// (см. CardTextView), параллельно с обычным text. text остаётся
    /// источником истины для поиска/AI/Spotlight; formattingData только
    /// восстанавливает визуальный стиль в редакторе и отбрасывается, если
    /// не совпадает с text (см. CardTextView.makeNSView) — например, после
    /// AI-действия, которое заменило text целиком plain-строкой.
    var formattingData: Data? = nil
    var tagColor: CardTagColor? = nil
    var privacyMode: CardPrivacyMode = .none
    /// true для карточек, созданных Ask AI/Summarize/Extract — в
    /// отличие от aiHighlightedCardIDs в BoardViewModel (временная подсветка,
    /// гаснет по клику, не персистится), это постоянная, сохранённая метка:
    /// такая карточка навсегда помечена маленькой иконкой sparkle. См. CardView.
    var isAIGenerated: Bool = false

    // MARK: Синк и бэкап

    /// Время последнего изменения каждой группы полей — по ним сливаются
    /// правки с разных Mac и из бэкапа (побеждает более новая группа, см.
    /// BoardMerger). Ставит их BoardChangeTracker при сохранении, а не
    /// точки мутаций по коду. У старых карточек без этих полей —
    /// Card.unknownDate, то есть "старше любой реальной правки".
    /// content — text + formattingData.
    var contentModifiedAt: Date = Card.unknownDate
    /// geometry — position, size, raisedAt.
    var geometryModifiedAt: Date = Card.unknownDate
    /// meta — Space карточки, tagColor, privacyMode, isAIGenerated.
    var metaModifiedAt: Date = Card.unknownDate
    /// Z-порядок: карточка с более поздним raisedAt рисуется выше. Раньше
    /// порядок держался только позицией в массиве Space — при синке это
    /// сдвигало бы индексы у всех карточек от одного подъёма одной.
    var raisedAt: Date = Card.unknownDate

    /// "Неизвестно когда" для данных, сохранённых до появления этих полей.
    static let unknownDate = Date(timeIntervalSince1970: 0)

    init(id: UUID = .init(), position: CGPoint, size: CGSize, text: String = "", tagColor: CardTagColor? = nil) {
        self.id = id
        self.position = position
        self.size = size
        self.text = text
        self.tagColor = tagColor
        // Новая карточка появляется поверх остальных.
        self.raisedAt = Date()
    }

    enum CodingKeys: String, CodingKey {
        case id, position, size, text, formattingData, tagColor, privacyMode, isAIGenerated
        case contentModifiedAt, geometryModifiedAt, metaModifiedAt, raisedAt
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        position = try container.decode(CGPoint.self, forKey: .position)
        size = try container.decode(CGSize.self, forKey: .size)
        tagColor = try container.decodeIfPresent(CardTagColor.self, forKey: .tagColor)
        privacyMode = try container.decodeIfPresent(CardPrivacyMode.self, forKey: .privacyMode) ?? .none

        // Устойчивое чтение обоих форматов: старые файлы на диске могли
        // сохранить text как AttributedString (в бытность RTF-эксперимента),
        // новые пишут его как обычную String.
        if let flatString = try? container.decode(String.self, forKey: .text) {
            text = flatString
        } else if let decodedAttributed = try? container.decode(AttributedString.self, forKey: .text) {
            text = String(decodedAttributed.characters)
        } else {
            text = ""
        }

        formattingData = try container.decodeIfPresent(Data.self, forKey: .formattingData)
        isAIGenerated = try container.decodeIfPresent(Bool.self, forKey: .isAIGenerated) ?? false
        contentModifiedAt = try container.decodeIfPresent(Date.self, forKey: .contentModifiedAt) ?? Card.unknownDate
        geometryModifiedAt = try container.decodeIfPresent(Date.self, forKey: .geometryModifiedAt) ?? Card.unknownDate
        metaModifiedAt = try container.decodeIfPresent(Date.self, forKey: .metaModifiedAt) ?? Card.unknownDate
        raisedAt = try container.decodeIfPresent(Date.self, forKey: .raisedAt) ?? Card.unknownDate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(position, forKey: .position)
        try container.encode(size, forKey: .size)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(formattingData, forKey: .formattingData)
        try container.encodeIfPresent(tagColor, forKey: .tagColor)
        try container.encode(privacyMode, forKey: .privacyMode)
        try container.encode(isAIGenerated, forKey: .isAIGenerated)
        try container.encode(contentModifiedAt, forKey: .contentModifiedAt)
        try container.encode(geometryModifiedAt, forKey: .geometryModifiedAt)
        try container.encode(metaModifiedAt, forKey: .metaModifiedAt)
        try container.encode(raisedAt, forKey: .raisedAt)
    }
}
