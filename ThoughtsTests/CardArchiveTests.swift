import CoreGraphics
import Foundation
import Testing
@testable import Thoughts

struct CardArchiveTests {
    private func card(_ text: String = "Hi") -> Card {
        Card(position: CGPoint(x: 10, y: 20), size: CGSize(width: 104, height: 104), text: text)
    }

    @Test func addTakeRoundTrip() throws {
        let archive = CardArchive(fileURL: nil)
        let c = card("Hello")
        archive.add([c], slot: 3)
        #expect(archive.items.count == 1 && archive.items[0].slot == 3)
        let record = try #require(archive.take(c.id))
        #expect(record.text == "Hello" && record.workspaceSlot == 3)
        #expect(archive.items.isEmpty)
    }

    @Test func oldItemsArePurged() {
        let archive = CardArchive(fileURL: nil)
        let old = Date().addingTimeInterval(-31 * 24 * 3600)
        archive.add([card("old")], slot: 1, now: old)
        archive.add([card("new")], slot: 1)
        #expect(archive.items.map(\.record.text) == ["new"])
    }

    @Test func persistsToDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        CardArchive(fileURL: url).add([card("kept")], slot: 2)
        #expect(CardArchive(fileURL: url).items.map(\.record.text) == ["kept"])
    }

    @Test func daysLeftCountsDown() {
        let archive = CardArchive(fileURL: nil)
        archive.add([card()], slot: 1, now: Date().addingTimeInterval(-10 * 24 * 3600))
        #expect(archive.daysLeft(archive.items[0]) == 20)
    }
}
