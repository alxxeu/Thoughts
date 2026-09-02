import SwiftUI

@Observable
final class Card: Identifiable, Codable {
    let id: UUID
    var position: CGPoint
    var size: CGSize
    var text: String

    init(id: UUID = .init(), position: CGPoint, size: CGSize, text: String = "") {
        self.id = id
        self.position = position
        self.size = size
        self.text = text
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
        text = try container.decode(String.self, forKey: .text)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(position, forKey: .position)
        try container.encode(size, forKey: .size)
        try container.encode(text, forKey: .text)
    }
}
