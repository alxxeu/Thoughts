// Card.swift
import SwiftUI

@Observable
final class Card: Identifiable {
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
}

extension Card {
    var frame: CGRect {
        CGRect(origin: position, size: size)
    }
}
