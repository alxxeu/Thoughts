import SwiftUI

enum EdgeHint: Equatable {
    enum Edge { case top, left, right, bottom }
    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    case edge(Edge, CGRect)
    case corner(Corner, CGRect)
}

@Observable
final class BoardViewModel {
    var workspaces: [Workspace] = []
    var activeSlot: Int = 1
    private var cardsByWorkspace: [Int: [Card]] = [:]

    var cards: [Card] {
        get { cardsByWorkspace[activeSlot] ?? [] }
        set { cardsByWorkspace[activeSlot] = newValue }
    }

    var activeWorkspace: Workspace? {
        workspaces.first { $0.slot == activeSlot }
    }

    private let store = BoardStore.shared
    private var saveTask: Task<Void, Never>?

    static let minCardSize: CGFloat = 120
    static let cardSizeStep: CGFloat = 60
    static let canvasSidePadding: CGFloat = 24
    static let topCreationLimit: CGFloat = 40

    init() {
        let loaded = store.load()
        workspaces = loaded.workspaces
        cardsByWorkspace = loaded.cardsByWorkspace
    }

    static func snap(_ value: CGFloat) -> CGFloat {
        max(minCardSize, (value / cardSizeStep).rounded() * cardSizeStep)
    }

    func switchWorkspace(to slot: Int) {
        activeSlot = min(9, max(1, slot))
    }
    
    func renameActiveWorkspace(to name: String) {
        guard let index = workspaces.firstIndex(where: { $0.slot == activeSlot }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        workspaces[index].name = trimmed.isEmpty ? "Space \(activeSlot)" : trimmed
        saveImmediately()
    }

    @discardableResult
    func addCard(at origin: CGPoint, size: CGSize) -> Card {
        let snapped = CGSize(width: Self.snap(size.width), height: Self.snap(size.height))
        let card = Card(position: origin, size: snapped)
        cards.append(card)
        saveImmediately()
        return card
    }

    func deleteCard(_ card: Card) {
        cards.removeAll { $0.id == card.id }
        saveImmediately()
    }

    func bringToFront(_ card: Card) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        var current = cards
        current.append(current.remove(at: index))
        cards = current
    }

    func saveImmediately() {
        saveTask?.cancel()
        saveTask = nil
        store.save(workspaces: workspaces, cardsByWorkspace: cardsByWorkspace)
    }

    func scheduleDebouncedSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self else { return }
            self.store.save(workspaces: self.workspaces, cardsByWorkspace: self.cardsByWorkspace)
        }
    }
}

extension BoardViewModel {
    static func placementPreview(
        movingId: UUID,
        movingPosition: CGPoint,
        movingSize: CGSize,
        others: [Card],
        canvasSize: CGSize
    ) -> CGPoint? {
        let gap: CGFloat = 16
        let activationDistance: CGFloat = 45
        let pad = canvasSidePadding
        let top = topCreationLimit
        let cardW = movingSize.width
        let cardH = movingSize.height

        var best: (distance: CGFloat, point: CGPoint)?

        func consider(_ x: CGFloat, _ y: CGFloat) {
            let distance = hypot(movingPosition.x - x, movingPosition.y - y)
            guard distance <= activationDistance else { return }
            if best == nil || distance < best!.distance {
                best = (distance, CGPoint(x: x, y: y))
            }
        }

        for other in others where other.id != movingId {
            let oPos = other.position
            let oSize = other.size

            let rightX = oPos.x + oSize.width + gap
            for y in [oPos.y, oPos.y + oSize.height / 2 - cardH / 2, oPos.y + oSize.height - cardH] {
                if rightX + cardW <= canvasSize.width - pad,
                   y >= top,
                   y + cardH <= canvasSize.height - pad {
                    consider(rightX, y)
                }
            }

            let leftX = oPos.x - cardW - gap
            for y in [oPos.y, oPos.y + oSize.height / 2 - cardH / 2, oPos.y + oSize.height - cardH] {
                if leftX >= pad,
                   y >= top,
                   y + cardH <= canvasSize.height - pad {
                    consider(leftX, y)
                }
            }

            let bottomY = oPos.y + oSize.height + gap
            for x in [oPos.x, oPos.x + oSize.width / 2 - cardW / 2, oPos.x + oSize.width - cardW] {
                if x >= pad,
                   x + cardW <= canvasSize.width - pad,
                   bottomY + cardH <= canvasSize.height - pad {
                    consider(x, bottomY)
                }
            }

            let topY = oPos.y - cardH - gap
            for x in [oPos.x, oPos.x + oSize.width / 2 - cardW / 2, oPos.x + oSize.width - cardW] {
                if x >= pad,
                   x + cardW <= canvasSize.width - pad,
                   topY >= top {
                    consider(x, topY)
                }
            }
        }

        return best?.point
    }

    static func edgeHints(
        movingPosition: CGPoint,
        movingSize: CGSize,
        canvasSize: CGSize
    ) -> [EdgeHint] {
        let pad = canvasSidePadding
        let top = topCreationLimit
        let lineThreshold: CGFloat = 35
        let cornerZone: CGFloat = 120
        let armLength: CGFloat = 60

        let distTop = movingPosition.y - top
        let distLeft = movingPosition.x - pad
        let distRight = canvasSize.width - pad - movingPosition.x - movingSize.width
        let distBottom = canvasSize.height - pad - movingPosition.y - movingSize.height

        struct CornerCandidate {
            let corner: EdgeHint.Corner
            let score: CGFloat
        }

        var candidates: [CornerCandidate] = []
        if distTop <= cornerZone && distLeft <= cornerZone {
            candidates.append(.init(corner: .topLeft, score: distTop + distLeft))
        }
        if distTop <= cornerZone && distRight <= cornerZone {
            candidates.append(.init(corner: .topRight, score: distTop + distRight))
        }
        if distBottom <= cornerZone && distLeft <= cornerZone {
            candidates.append(.init(corner: .bottomLeft, score: distBottom + distLeft))
        }
        if distBottom <= cornerZone && distRight <= cornerZone {
            candidates.append(.init(corner: .bottomRight, score: distBottom + distRight))
        }

        if let best = candidates.min(by: { $0.score < $1.score }) {
            let frame: CGRect
            switch best.corner {
            case .topLeft:
                frame = CGRect(x: pad, y: top, width: armLength, height: armLength)
            case .topRight:
                frame = CGRect(x: canvasSize.width - pad - armLength, y: top, width: armLength, height: armLength)
            case .bottomLeft:
                frame = CGRect(x: pad, y: canvasSize.height - pad - armLength, width: armLength, height: armLength)
            case .bottomRight:
                frame = CGRect(x: canvasSize.width - pad - armLength, y: canvasSize.height - pad - armLength, width: armLength, height: armLength)
            }
            return [.corner(best.corner, frame)]
        }

        var hints: [EdgeHint] = []
        if distTop <= lineThreshold {
            hints.append(.edge(.top, CGRect(x: movingPosition.x, y: top, width: movingSize.width, height: 3)))
        }
        if distBottom <= lineThreshold {
            hints.append(.edge(.bottom, CGRect(x: movingPosition.x, y: canvasSize.height - pad, width: movingSize.width, height: 3)))
        }
        if distLeft <= lineThreshold {
            hints.append(.edge(.left, CGRect(x: pad, y: movingPosition.y, width: 3, height: movingSize.height)))
        }
        if distRight <= lineThreshold {
            hints.append(.edge(.right, CGRect(x: canvasSize.width - pad, y: movingPosition.y, width: 3, height: movingSize.height)))
        }
        return hints
    }

    static func snappedToEdges(
        position: CGPoint,
        size: CGSize,
        canvasSize: CGSize
    ) -> CGPoint {
        let pad = canvasSidePadding
        let top = topCreationLimit
        let snapThreshold: CGFloat = 30

        var x = position.x
        var y = position.y

        let distToLeft = x - pad
        let distToRight = canvasSize.width - pad - x - size.width
        let distToTop = y - top
        let distToBottom = canvasSize.height - pad - y - size.height

        if distToLeft < snapThreshold {
            x = pad
        } else if distToRight < snapThreshold {
            x = canvasSize.width - pad - size.width
        }

        if distToTop < snapThreshold {
            y = top
        } else if distToBottom < snapThreshold {
            y = canvasSize.height - pad - size.height
        }

        return CGPoint(x: x, y: y)
    }
}
