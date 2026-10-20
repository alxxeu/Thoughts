import Foundation
import Testing
@testable import Thoughts

struct KanbanBoardTests {
    private let sample = "::: board\n# Plan\n- Book tram tour\n- Offline maps\n||\n# To go\n- Pack\n||\n# Ready"

    @Test func parsesColumnsTitlesAndItems() throws {
        let board = try #require(KanbanBoard.parse(sample))
        #expect(board.columns.map(\.title) == ["Plan", "To go", "Ready"])
        #expect(board.columns.map { $0.items.map(\.text) } == [["Book tram tour", "Offline maps"], ["Pack"], []])
    }

    @Test func roundTripIsStable() throws {
        let board = try #require(KanbanBoard.parse(sample))
        #expect(board.serialized() == sample)
        #expect(KanbanBoard.parse(board.serialized())?.serialized() == sample)
    }

    @Test func templateTextIsCanonical() throws {
        let board = try #require(KanbanBoard.parse(CardTemplate.kanban.text))
        #expect(board.columns.count == 3)
        #expect(board.columns[0].title == "Plan")
        #expect(board.columns[0].items.map(\.text) == [""])
        #expect(board.columns[1].title.isEmpty && board.columns[2].title.isEmpty)
        #expect(board.serialized() == CardTemplate.kanban.text)
    }

    @Test func needsTheMarker() {
        #expect(KanbanBoard.parse("# Plan\n- a") == nil)
        #expect(!KanbanBoard.isBoard("text\n::: board"))
        #expect(KanbanBoard.isBoard("::: board"))
        #expect(KanbanBoard.isBoard("::: board\n"))
    }

    @Test func multilineItemsKeepTheirLines() throws {
        let text = "::: board\n# A\n- first\n  second line\n- next"
        let board = try #require(KanbanBoard.parse(text))
        #expect(board.columns[0].items.map(\.text) == ["first\nsecond line", "next"])
        #expect(board.serialized() == text)
    }

    @Test func strayLinesBecomeItemsInsteadOfBeingLost() throws {
        let board = try #require(KanbanBoard.parse("::: board\nplain line\n# not a title\n- real"))
        #expect(board.columns[0].title == "")
        #expect(board.columns[0].items.map(\.text) == ["plain line", "# not a title", "real"])
    }

    @Test func emptyBoardAndEmptyColumns() throws {
        let empty = try #require(KanbanBoard.parse("::: board"))
        #expect(empty.columns.count == 1)
        let board = try #require(KanbanBoard.parse("::: board\n||\n||\n# C"))
        #expect(board.columns.map(\.title) == ["", "", "C"])
        #expect(KanbanBoard.parse(board.serialized())?.columns.map(\.title) == ["", "", "C"])
    }

    @Test func editsAddRemoveSetText() throws {
        var board = try #require(KanbanBoard.parse(sample))
        let id = try #require(board.addItem(toColumn: 2, text: "done"))
        #expect(board.columns[2].items.map(\.text) == ["done"])
        board.setText("finished", of: id)
        #expect(board.columns[2].items[0].text == "finished")
        board.removeItem(id)
        #expect(board.columns[2].items.isEmpty)
        board.setTitle("Later", ofColumn: 2)
        #expect(board.serialized().hasSuffix("# Later"))
    }

    @Test func movingBetweenAndWithinColumns() throws {
        var board = try #require(KanbanBoard.parse(sample))
        let tram = board.columns[0].items[0].id
        board.moveItem(tram, toColumn: 2, at: 0)
        #expect(board.columns.map { $0.items.map(\.text) } == [["Offline maps"], ["Pack"], ["Book tram tour"]])

        // Внутри колонки: «в конец» и «в начало».
        var inner = try #require(KanbanBoard.parse("::: board\n- a\n- b\n- c"))
        let a = inner.columns[0].items[0].id
        inner.moveItem(a, toColumn: 0, at: 3)
        #expect(inner.columns[0].items.map(\.text) == ["b", "c", "a"])
        let c = inner.columns[0].items[1].id
        inner.moveItem(c, toColumn: 0, at: 0)
        #expect(inner.columns[0].items.map(\.text) == ["c", "b", "a"])
        // Положить на своё же место — ничего не меняется.
        let b = inner.columns[0].items[1].id
        inner.moveItem(b, toColumn: 0, at: 1)
        inner.moveItem(b, toColumn: 0, at: 2)
        #expect(inner.columns[0].items.map(\.text) == ["c", "b", "a"])
    }

    @Test func lastColumnIsNeverRemoved() throws {
        var board = try #require(KanbanBoard.parse("::: board\n# A\n||\n# B"))
        board.removeColumn(0)
        board.removeColumn(0)
        #expect(board.columns.map(\.title) == ["B"])
    }
}
