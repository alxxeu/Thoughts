import Foundation
import Testing
@testable import Thoughts

@MainActor
struct BoardMergerTests {
    @Test func newerSideWinsPerFieldGroup() {
        let id = UUID()
        // Текст новее на этом Mac, геометрия и мета — на другом.
        let local = makeCardRecord(id: id, slot: 1, text: "local text", x: 10, contentAt: 300, geometryAt: 100, metaAt: 100)
        let remote = makeCardRecord(id: id, slot: 3, text: "remote text", x: 500, contentAt: 200, geometryAt: 400, metaAt: 400)

        let merged = BoardMerger.merge(local, remote)

        #expect(merged.text == "local text")
        #expect(merged.contentModifiedAt == local.contentModifiedAt)
        #expect(merged.x == 500)
        #expect(merged.geometryModifiedAt == remote.geometryModifiedAt)
        #expect(merged.workspaceSlot == 3)
    }

    @Test func tieKeepsBase() {
        let id = UUID()
        let local = makeCardRecord(id: id, text: "local", x: 10)
        let remote = makeCardRecord(id: id, text: "remote", x: 500)
        #expect(BoardMerger.merge(local, remote) == local)
    }

    @Test func customWorkspaceNameBeatsNewerDefault() {
        let named = WorkspaceRecord(slot: 4, name: "Ideas", isProtected: false, modifiedAt: Date(timeIntervalSince1970: 100))
        let reset = WorkspaceRecord(slot: 4, name: Workspace.defaultName(forSlot: 4), isProtected: false, modifiedAt: Date(timeIntervalSince1970: 200))
        #expect(BoardMerger.merge(named, reset, keepProtection: false).name == "Ideas")
    }

    @Test func importKeepsProtectionFromEitherSide() {
        let local = BoardSnapshot(
            workspaces: [WorkspaceRecord(slot: 1, name: "Private", isProtected: true, modifiedAt: Date(timeIntervalSince1970: 100))],
            cards: [makeCardRecord(text: "only here")]
        )
        let incoming = BoardSnapshot(
            workspaces: [WorkspaceRecord(slot: 1, name: "Private", isProtected: false, modifiedAt: Date(timeIntervalSince1970: 200))],
            cards: [makeCardRecord(text: "only in backup")]
        )
        let merged = BoardMerger.merge(local: local, incoming: incoming)
        #expect(merged.workspaces.first?.isProtected == true)
        #expect(Set(merged.cards.map(\.text)) == ["only here", "only in backup"])
    }
}
