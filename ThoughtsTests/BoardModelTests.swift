import Foundation
import Testing
@testable import Thoughts

@MainActor
struct BoardModelTests {
    private let boardURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ThoughtsTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("board.json")

    init() throws {
        try FileManager.default.createDirectory(at: boardURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func makeBoard() -> BoardModel {
        BoardModel(store: BoardStore(fileURL: boardURL))
    }

    /// Пришедшее из iCloud сохраняется на диск, но не уходит обратно как
    /// локальная правка; настоящая локальная правка — уходит.
    @Test func remoteCardIsSavedButNotEchoedBack() {
        let board = makeBoard()
        var echoed: [BoardChangeSet] = []
        board.onLocalChanges = { echoed.append($0) }

        let remote = makeCardRecord(slot: 2, text: "From Mac")
        board.applyRemote(cards: [remote], deletedCardIDs: [], workspaces: [])
        #expect(board.cardsByWorkspace[2]?.first?.text == "From Mac")
        #expect(makeBoard().cardsByWorkspace[2]?.first?.text == "From Mac")

        board.saveImmediately()
        #expect(echoed.isEmpty)

        board.cardsByWorkspace[2]?.first?.text = "Edited here"
        board.saveImmediately()
        #expect(echoed.last?.savedCards == [remote.id])
    }

    /// Текст карточки под курсором не меняется под руками — правка ждёт,
    /// пока фокус не уйдёт.
    @Test func remoteTextForEditedCardWaitsForFocusToLeave() {
        let board = makeBoard()
        let original = makeCardRecord(text: "Mine", contentAt: 100)
        board.applyRemote(cards: [original], deletedCardIDs: [], workspaces: [])
        board.editingCardID = original.id

        board.applyRemote(cards: [makeCardRecord(id: original.id, text: "Theirs", contentAt: 200)], deletedCardIDs: [], workspaces: [])
        #expect(board.cardsByWorkspace[1]?.first?.text == "Mine")

        board.editingCardID = nil
        #expect(board.cardsByWorkspace[1]?.first?.text == "Theirs")
    }

    @Test func remoteDeletionRemovesCardAndNotifies() {
        let board = makeBoard()
        let card = makeCardRecord()
        board.applyRemote(cards: [card], deletedCardIDs: [], workspaces: [])
        var deleted: Set<UUID> = []
        board.onRemoteDeletion = { deleted = $0 }

        board.applyRemote(cards: [], deletedCardIDs: [card.id], workspaces: [])
        #expect(board.cardsByWorkspace[1]?.isEmpty == true)
        #expect(deleted == [card.id])
    }
}
