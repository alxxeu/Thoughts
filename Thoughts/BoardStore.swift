import Foundation

private struct BoardData: Codable {
    var workspaces: [Workspace]
    var cardsByWorkspace: [Int: [Card]]
}

final class BoardStore {
    static let shared = BoardStore()

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let folder = appSupport.appendingPathComponent("Thoughts", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        fileURL = folder.appendingPathComponent("board.json")
    }

    func load() -> (workspaces: [Workspace], cardsByWorkspace: [Int: [Card]]) {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(BoardData.self, from: data) {
            var workspaces = decoded.workspaces
            for slot in 1...9 where !workspaces.contains(where: { $0.slot == slot }) {
                workspaces.append(Workspace(slot: slot, name: "Space \(slot)"))
            }
            workspaces.sort { $0.slot < $1.slot }
            return (workspaces, decoded.cardsByWorkspace)
        }

        // Миграция со старой версии до появления Spaces (единый cards.json → Space 1)
        let legacyURL = fileURL.deletingLastPathComponent().appendingPathComponent("cards.json")
        if let legacyData = try? Data(contentsOf: legacyURL),
           let legacyCards = try? JSONDecoder().decode([Card].self, from: legacyData) {
            let workspaces = defaultWorkspaces()
            let cardsByWorkspace = [1: legacyCards]
            save(workspaces: workspaces, cardsByWorkspace: cardsByWorkspace)
            try? FileManager.default.removeItem(at: legacyURL)
            return (workspaces, cardsByWorkspace)
        }

        return (defaultWorkspaces(), [:])
    }

    func save(workspaces: [Workspace], cardsByWorkspace: [Int: [Card]]) {
        let data = BoardData(workspaces: workspaces, cardsByWorkspace: cardsByWorkspace)
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }

    private func defaultWorkspaces() -> [Workspace] {
        (1...9).map { Workspace(slot: $0, name: "Space \($0)") }
    }
}
