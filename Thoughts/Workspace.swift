import Foundation

struct Workspace: Identifiable, Codable, Equatable {
    let id: UUID
    var slot: Int
    var name: String

    init(id: UUID = .init(), slot: Int, name: String) {
        self.id = id
        self.slot = slot
        self.name = name
    }
}
