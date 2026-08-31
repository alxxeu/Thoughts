// BoardViewModel.swift
import SwiftUI

@Observable
final class BoardViewModel {
    var cards: [Card] = []
    var canvasOffset: CGSize = .zero
    var placementPreview: CGPoint? = nil

    func addCard(at point: CGPoint) {
        let newCard = Card(position: findPlacementPreview(near: point), size: CGSize(width: 320, height: 220))
        cards.append(newCard)
    }

    private func findPlacementPreview(near point: CGPoint) -> CGPoint {
        var candidate = point
        let spacing: CGFloat = 32
        var tries = 0
        while tries < 100 {
            let frame = CGRect(origin: candidate, size: CGSize(width: 320, height: 220))
            if !cards.contains(where: { $0.frame.intersects(frame) }) {
                return candidate
            }
            candidate.x += spacing
            candidate.y += spacing
            tries += 1
        }
        return point
    }
}
