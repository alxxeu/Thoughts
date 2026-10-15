import Foundation
import Testing
@testable import Thoughts

@MainActor
struct BackupCodecTests {
    private let snapshot = BoardSnapshot(
        workspaces: [WorkspaceRecord(slot: 2, name: "Work", isProtected: true, modifiedAt: Date(timeIntervalSince1970: 50))],
        cards: [makeCardRecord(slot: 2, text: "Secret plan")]
    )

    @Test func roundTripWithoutPassword() throws {
        let data = try BackupCodec.encode(snapshot, password: nil)
        #expect(try BackupCodec.decode(data, password: nil) == snapshot)
    }

    @Test func roundTripWithPassword() throws {
        let data = try BackupCodec.encode(snapshot, password: "correct horse")
        #expect(try BackupCodec.inspect(data).isEncrypted)
        // Текст карточки не должен лежать в файле открытым.
        #expect(String(decoding: data, as: UTF8.self).contains("Secret plan") == false)
        #expect(try BackupCodec.decode(data, password: "correct horse") == snapshot)
    }

    @Test func wrongOrMissingPasswordIsRejected() throws {
        let data = try BackupCodec.encode(snapshot, password: "correct horse")
        #expect(throws: BackupCodec.BackupError.wrongPassword) {
            try BackupCodec.decode(data, password: "wrong horse")
        }
        #expect(throws: BackupCodec.BackupError.passwordRequired) {
            try BackupCodec.decode(data, password: nil)
        }
    }

    @Test func invalidRecordsAreDroppedOrFixed() throws {
        let duplicateID = UUID()
        let dirty = BoardSnapshot(
            workspaces: [
                WorkspaceRecord(slot: 1, name: "One", isProtected: false, modifiedAt: .now),
                WorkspaceRecord(slot: 10, name: "Ten", isProtected: false, modifiedAt: .now)
            ],
            cards: [
                makeCardRecord(id: duplicateID, text: "first"),
                makeCardRecord(id: duplicateID, text: "duplicate"),
                makeCardRecord(slot: 10),
                makeCardRecord(width: 1)
            ]
        )
        let decoded = try BackupCodec.decode(try BackupCodec.encode(dirty, password: nil), password: nil)

        #expect(decoded.workspaces.map(\.slot) == [1])
        #expect(decoded.cards.count == 2)
        #expect(decoded.cards.first?.text == "first")
        #expect(decoded.cards.allSatisfy { $0.width >= BoardViewModel.minCardSize })
    }

    @Test func otherFilesAreNotBackups() {
        #expect(throws: BackupCodec.BackupError.notABackup) {
            try BackupCodec.decode(Data("{\"hello\": 1}".utf8), password: nil)
        }
    }
}
