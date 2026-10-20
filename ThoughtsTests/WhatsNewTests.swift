import Foundation
import Testing
@testable import Thoughts

@MainActor
struct WhatsNewTests {
    private func freshDefaults() -> UserDefaults {
        let name = "WhatsNewTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func firstInstallShowsNothingAndRemembersVersion() {
        let defaults = freshDefaults()
        #expect(WhatsNew.pendingNote(defaults: defaults, version: "1.4", hasCompletedTour: false) == nil)
        #expect(WhatsNew.pendingNote(defaults: defaults, version: "1.4", hasCompletedTour: true) == nil)
    }

    @Test func updateShowsNoteUntilSeen() {
        let defaults = freshDefaults()
        // Пользователь прошлой версии: тур пройден, версии плашка не помнит.
        #expect(WhatsNew.pendingNote(defaults: defaults, version: "1.4", hasCompletedTour: true)?.version == "1.4")
        WhatsNew.markSeen(defaults: defaults, version: "1.4")
        #expect(WhatsNew.pendingNote(defaults: defaults, version: "1.4", hasCompletedTour: true) == nil)
        // Версии без заметки — без плашки.
        #expect(WhatsNew.pendingNote(defaults: defaults, version: "9.9", hasCompletedTour: true) == nil)
    }

    @Test func noteBecomesMarkdown() {
        let note = ReleaseNote(version: "2.0", sections: [
            .init(title: "New", items: ["**A**", "B"]),
            .init(title: "Note", items: ["C", "D"])
        ])
        #expect(WhatsNew.markdown(for: note) == "# What\u{2019}s new in 2.0\n\n## New\n- **A**\n- B\n\n--\n\n> C\n> D")
    }

    @Test func noteWithBoardBecomesKanban() throws {
        let note = ReleaseNote(version: "2.0", sections: [], board: [
            .init(title: "New", items: ["A", "B"]),
            .init(title: "Fixed", items: ["C"])
        ])
        let text = WhatsNew.cardText(for: note)
        #expect(text == "::: board\n## New\n- A\n- B\n||\n## Fixed\n- C")
        let board = try #require(KanbanBoard.parse(text))
        #expect(board.columns.map(\.title) == ["New", "Fixed"])
        #expect(board.columns.map { $0.items.count } == [2, 1])
    }

    @Test func currentReleaseHasAWhatsNewBoard() {
        let note = ReleaseNotes.all.first
        #expect(note?.version == "1.4.1")
        #expect(note?.board?.map(\.title) == ["New", "Improved", "Fixed"])
    }
}
