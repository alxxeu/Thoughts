import Foundation

struct Workspace: Identifiable, Codable, Equatable {
    let id: UUID
    var slot: Int
    var name: String
    /// Персистентный флаг: этот Space защищён Space Lock (включён через
    /// Cmd+L). Не путать с runtime-состоянием "разблокирован в этой
    /// сессии" — оно хранится отдельно в BoardViewModel и никогда не
    /// сохраняется на диск.
    var isProtected: Bool
    /// Последнее изменение имени/защиты — для слияния с другими Mac и
    /// бэкапом (см. BoardMerger). Ставит BoardChangeTracker при сохранении.
    var modifiedAt: Date

    init(id: UUID = .init(), slot: Int, name: String, isProtected: Bool = false, modifiedAt: Date = Card.unknownDate) {
        self.id = id
        self.slot = slot
        self.name = name
        self.isProtected = isProtected
        self.modifiedAt = modifiedAt
    }

    /// Единственный источник фоллбек-имени "Space N" — до этого было
    /// продублировано как raw string interpolation в 7 местах в 4 файлах.
    static func defaultName(forSlot slot: Int) -> String {
        "Space \(slot)"
    }

    enum CodingKeys: String, CodingKey {
        case id, slot, name, isProtected, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        slot = try container.decode(Int.self, forKey: .slot)
        name = try container.decode(String.self, forKey: .name)
        // decodeIfPresent — старые сохранённые board.json не содержат этого
        // поля вообще, и без явного fallback декодирование всей структуры
        // упало бы, стерев все существующие Spaces и карточки.
        isProtected = try container.decodeIfPresent(Bool.self, forKey: .isProtected) ?? false
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Card.unknownDate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(slot, forKey: .slot)
        try container.encode(name, forKey: .name)
        try container.encode(isProtected, forKey: .isProtected)
        try container.encode(modifiedAt, forKey: .modifiedAt)
    }
}
