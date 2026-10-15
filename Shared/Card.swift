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
    /// Markdown — единственный формат текста: хранится, синхронизируется и
    /// редактируется как есть (см. MarkdownStyler). Карточки старого формата
    /// переводятся при чтении (см. MarkdownMigration).
    var text: String = ""
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
    /// content — text.
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

    /// Карточка пришла с диска в старом формате и при чтении переведена в
    /// Markdown — BoardStore сохраняет копию исходного файла. Не сохраняется.
    @ObservationIgnored private(set) var wasMigratedToMarkdown = false

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
        case id, position, size, text, textFormat, formattingData, tagColor, privacyMode, isAIGenerated
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

        let textFormat = try container.decodeIfPresent(Int.self, forKey: .textFormat) ?? MarkdownMigration.legacyFormat
        if textFormat < MarkdownMigration.markdownFormat {
            let formattingData = try container.decodeIfPresent(Data.self, forKey: .formattingData)
            text = MarkdownMigration.markdown(text: text, formattingData: formattingData)
            wasMigratedToMarkdown = true
        }
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
        try container.encode(MarkdownMigration.markdownFormat, forKey: .textFormat)
        try container.encodeIfPresent(tagColor, forKey: .tagColor)
        try container.encode(privacyMode, forKey: .privacyMode)
        try container.encode(isAIGenerated, forKey: .isAIGenerated)
        try container.encode(contentModifiedAt, forKey: .contentModifiedAt)
        try container.encode(geometryModifiedAt, forKey: .geometryModifiedAt)
        try container.encode(metaModifiedAt, forKey: .metaModifiedAt)
        try container.encode(raisedAt, forKey: .raisedAt)
    }
}

/// Сетка размеров карточек на холсте Mac; минимальный размер нужен и ядру
/// (BackupCodec чинит карточки меньше него).
extension Card {
    static let sizeStep: CGFloat = 60
    /// Зазор между стыкующимися карточками — тот же, что использует
    /// placementPreview при стековке. Обе величины обязаны идти из одной
    /// константы: card-size формула size(k) = k*sizeStep - gap
    /// устроена так, что любые две стыкующиеся карточки (k1 и k2 тайлов)
    /// с этим зазором между ними в сумме дают ровно size(k1+k2) — то есть
    /// колонка из нескольких карточек всегда идеально совпадает по краю
    /// с одной карточкой такой же суммарной "тайловости", как у нативных
    /// виджетов macOS (medium = 2 tile + 1 gap, а не просто 2 tile).
    static let gap: CGFloat = 16
    static let minSize: CGFloat = 2 * sizeStep - gap
}
