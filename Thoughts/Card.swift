import SwiftUI

@Observable
final class Card: Identifiable, Codable {
    let id: UUID
    var position: CGPoint
    var size: CGSize
    var text: AttributedString = AttributedString("") // Нативный Rich Text тип

    init(id: UUID = .init(), position: CGPoint, size: CGSize, text: String = "") {
        self.id = id
        self.position = position
        self.size = size
        self.text = AttributedString(text)
    }

    var frame: CGRect {
        CGRect(origin: position, size: size)
    }

    enum CodingKeys: String, CodingKey {
        case id, position, size, text
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        position = try container.decode(CGPoint.self, forKey: .position)
        size = try container.decode(CGSize.self, forKey: .size)
        
        // 1. Пытаемся нативно декодировать AttributedString (если он был сохранен с форматированием)
        if let decodedText = try? container.decode(AttributedString.self, forKey: .text) {
            text = decodedText
        }
        // 2. Логика обратной совместимости: если в файле лежит старая плоская String,
        // мы безопасно прочитаем её и обернем в AttributedString, предотвращая вылет
        else if let flatString = try? container.decode(String.self, forKey: .text) {
            text = AttributedString(flatString)
        }
        // 3. Страховка на случай непредвиденных сбоев данных
        else {
            text = AttributedString("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(position, forKey: .position)
        try container.encode(size, forKey: .size)
        
        // Нативно кодируем AttributedString в JSON со всеми стилями букв
        try container.encode(text, forKey: .text)
    }
}
