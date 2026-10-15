import Foundation
import Testing
@testable import Thoughts

@MainActor
struct BoardStoreTests {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ThoughtsTests-\(UUID().uuidString)", isDirectory: true)
    private var boardURL: URL { folder.appendingPathComponent("board.json") }

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    @Test func savedBoardLoadsBack() {
        let card = Card(position: CGPoint(x: 40, y: 60), size: CGSize(width: 104, height: 104), text: "Keep me")
        BoardStore(fileURL: boardURL).save(workspaces: [Workspace(slot: 3, name: "Three")], cardsByWorkspace: [3: [card]])

        let loaded = BoardStore(fileURL: boardURL).load()
        #expect(loaded.workspaces.count == 9)
        #expect(loaded.workspaces.first { $0.slot == 3 }?.name == "Three")
        #expect(loaded.cardsByWorkspace[3]?.first?.text == "Keep me")
    }

    /// Карточка с тегом, которого эта версия не знает (файл от более новой
    /// сборки), раньше обнуляла всю доску, и первое сохранение её затирало.
    @Test func unreadableBoardIsSetAsideNotOverwritten() throws {
        let card = Card(position: CGPoint(x: 0, y: 0), size: CGSize(width: 104, height: 104), text: "Precious", tagColor: .red)
        BoardStore(fileURL: boardURL).save(workspaces: [Workspace(slot: 1, name: "One")], cardsByWorkspace: [1: [card]])
        let original = try String(contentsOf: boardURL, encoding: .utf8)
        let future = original.replacingOccurrences(of: "\"red\"", with: "\"pink\"")
        #expect(future != original)
        try future.write(to: boardURL, atomically: true, encoding: .utf8)

        let store = BoardStore(fileURL: boardURL)
        let loaded = store.load()
        #expect(loaded.cardsByWorkspace.isEmpty)

        let setAside = try #require(store.unreadableFileURL)
        #expect(setAside != boardURL)
        #expect(setAside.lastPathComponent.hasPrefix("board.unreadable-"))
        #expect(try String(contentsOf: setAside, encoding: .utf8) == future)

        store.save(workspaces: loaded.workspaces, cardsByWorkspace: loaded.cardsByWorkspace)
        #expect(try String(contentsOf: setAside, encoding: .utf8) == future)
    }
}
