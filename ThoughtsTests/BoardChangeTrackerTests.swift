import Foundation
import Testing
@testable import Thoughts

@MainActor
struct BoardChangeTrackerTests {
    private let then = Date(timeIntervalSince1970: 1_000)
    private let now = Date(timeIntervalSince1970: 2_000)

    private func makeCard() -> Card {
        let card = Card(position: CGPoint(x: 40, y: 60), size: CGSize(width: 104, height: 104), text: "Hi")
        card.contentModifiedAt = then
        card.geometryModifiedAt = then
        card.metaModifiedAt = then
        return card
    }

    @Test func textEditStampsOnlyContent() {
        let card = makeCard()
        var workspaces = [Workspace(slot: 1, name: "Space 1")]
        let tracker = BoardChangeTracker(workspaces: workspaces, cardsByWorkspace: [1: [card]])

        card.text = "Hi there"
        let changes = tracker.stamp(workspaces: &workspaces, cardsByWorkspace: [1: [card]], now: now)

        #expect(changes.savedCards == [card.id])
        #expect(card.contentModifiedAt == now)
        #expect(card.geometryModifiedAt == then)
        #expect(card.metaModifiedAt == then)
    }

    @Test func noChangeMeansEmptySet() {
        let card = makeCard()
        var workspaces = [Workspace(slot: 1, name: "Space 1")]
        let tracker = BoardChangeTracker(workspaces: workspaces, cardsByWorkspace: [1: [card]])
        #expect(tracker.stamp(workspaces: &workspaces, cardsByWorkspace: [1: [card]], now: now).isEmpty)
    }

    @Test func newMovedAndDeletedCards() {
        let kept = makeCard()
        let deleted = makeCard()
        var workspaces = [Workspace(slot: 1, name: "Space 1")]
        let tracker = BoardChangeTracker(workspaces: workspaces, cardsByWorkspace: [1: [kept, deleted]])

        let added = makeCard()
        workspaces[0].name = "Inbox"
        let changes = tracker.stamp(workspaces: &workspaces, cardsByWorkspace: [2: [kept], 1: [added]], now: now)

        #expect(changes.savedCards == [kept.id, added.id])
        #expect(changes.deletedCards == [deleted.id])
        #expect(changes.savedWorkspaces == [1])
        #expect(workspaces[0].modifiedAt == now)
        // Перенос в другой Space — это мета, не текст.
        #expect(kept.metaModifiedAt == now)
        #expect(kept.contentModifiedAt == then)
        #expect(added.contentModifiedAt == now)
    }
}
