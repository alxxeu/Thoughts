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

@MainActor
struct BoardModelCardTests {
    private let boardURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ThoughtsTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("board.json")

    init() throws {
        try FileManager.default.createDirectory(at: boardURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    /// Карточка с iPhone сохраняется и уходит в синк; удаление — тоже.
    @Test func addAndDeleteCardAreSavedAndSynced() {
        let board = BoardModel(store: BoardStore(fileURL: boardURL))
        var changes: [BoardChangeSet] = []
        board.onLocalChanges = { changes.append($0) }

        let card = board.addCard(text: "Buy oat milk", slot: 3)
        #expect(BoardModel(store: BoardStore(fileURL: boardURL)).cardsByWorkspace[3]?.first?.text == "Buy oat milk")
        #expect(changes.last?.savedCards == [card.id])

        board.deleteCard(id: card.id)
        #expect(board.cardsByWorkspace[3]?.isEmpty == true)
        #expect(changes.last?.deletedCards == [card.id])
    }

    /// Rename — общий для Mac и iPhone: пробелы по краям, предел длины, пустое — имя по умолчанию.
    @Test func renameWorkspaceTrimsLimitsAndFallsBack() {
        let board = BoardModel(store: BoardStore(fileURL: boardURL))
        board.renameWorkspace(slot: 2, to: "  Ideas  ")
        #expect(board.workspaces.first { $0.slot == 2 }?.name == "Ideas")
        board.renameWorkspace(slot: 2, to: String(repeating: "x", count: 40))
        #expect(board.workspaces.first { $0.slot == 2 }?.name.count == Workspace.maxNameLength)
        board.renameWorkspace(slot: 2, to: "   ")
        #expect(board.workspaces.first { $0.slot == 2 }?.name == Workspace.defaultName(forSlot: 2))
    }
}
