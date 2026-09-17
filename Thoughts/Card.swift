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

    init(id: UUID = .init(), position: CGPoint, size: CGSize, text: String = "", tagColor: CardTagColor? = nil) {
        self.id = id
        self.position = position
        self.size = size
        self.text = text
        self.tagColor = tagColor
    }

    enum CodingKeys: String, CodingKey {
        case id, position, size, text, formattingData, tagColor, privacyMode
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
    }
}
