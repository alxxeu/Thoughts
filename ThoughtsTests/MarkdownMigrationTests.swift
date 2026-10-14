import AppKit
import Testing
@testable import Thoughts

@MainActor
struct MarkdownMigrationTests {
    private func archive(_ attributed: NSAttributedString) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: attributed, requiringSecureCoding: true)
    }

    @Test func formattedCardBecomesMarkdown() throws {
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15)]
        let s = NSMutableAttributedString(string: "Buy ", attributes: base)
        s.append(NSAttributedString(string: "milk", attributes: [.font: NSFont.boldSystemFont(ofSize: 15)]))
        s.append(NSAttributedString(string: " at ", attributes: base))
        s.append(NSAttributedString(string: "shop", attributes: base.merging([.link: URL(string: "https://shop.com")!]) { $1 }))
        s.append(NSAttributedString(string: "\n\u{2022} one\n", attributes: base))
        s.append(NSAttributedString(attachment: DividerAttachment()))
        s.append(NSAttributedString(string: "\n2. two", attributes: base))

        let markdown = MarkdownMigration.markdown(text: s.string, formattingData: try archive(s))
        #expect(markdown == "Buy **milk** at [shop](https://shop.com)\n- one\n---\n2. two")
    }

    @Test func leadingTabsAndSpacesSurvive() throws {
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15)]
        let s = NSMutableAttributedString(string: "\tplain\n", attributes: base)
        s.append(NSAttributedString(string: "\t bold \t", attributes: [.font: NSFont.boldSystemFont(ofSize: 15)]))
        let markdown = MarkdownMigration.markdown(text: s.string, formattingData: try archive(s))
        #expect(markdown == "\tplain\n\t **bold** \t")
    }

    @Test func autoLinkStaysBareUrl() throws {
        let url = "https://example.com/~me?a=b"
        let s = NSAttributedString(string: url, attributes: [.link: URL(string: url)!])
        #expect(MarkdownMigration.markdown(text: url, formattingData: try archive(s)) == url)
    }

    @Test func plainTextKeepsItsLook() {
        let text = "2*3*4 and **x** and site.com/~me?a=b\n# not a heading\n\u{2022} item\u{FFFC}"
        let markdown = MarkdownMigration.markdown(text: text, formattingData: nil)
        #expect(MarkdownStyler.parse(markdown).flatMap(\.inlines).isEmpty)
        #expect(markdown.contains("site.com/~me?a=b"))
        #expect(markdown.contains(##"\# not a heading"##))
        #expect(MarkdownStyler.plainText(markdown).hasPrefix("2*3*4 and **x** and site.com/~me?a=b\n# not a heading"))
    }

    @Test func mismatchedArchiveFallsBackToText() throws {
        let stale = NSAttributedString(string: "old", attributes: [.font: NSFont.boldSystemFont(ofSize: 15)])
        #expect(MarkdownMigration.markdown(text: "new text", formattingData: try archive(stale)) == "new text")
    }

    @Test func legacyCardIsMigratedOnceOnDecode() throws {
        let legacy = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","position":[0,0],"size":[104,104],"text":"a*b*c"}"#
        let card = try JSONDecoder().decode(Card.self, from: Data(legacy.utf8))
        #expect(card.wasMigratedToMarkdown)
        #expect(card.text == #"a\*b\*c"#)

        // Сохранённая карточка уже в Markdown — повторного экранирования нет.
        let again = try JSONDecoder().decode(Card.self, from: JSONEncoder().encode(card))
        #expect(!again.wasMigratedToMarkdown)
        #expect(again.text == #"a\*b\*c"#)
    }

    @Test func legacyBackupRecordIsMigratedOnce() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(makeCardRecord(text: "x"))) as! [String: Any]
        legacy["text"] = "\u{2022} a*b*"
        legacy.removeValue(forKey: "textFormat")
        let record = try JSONDecoder().decode(CardRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(record.text == #"- a\*b\*"#)
        let again = try JSONDecoder().decode(CardRecord.self, from: JSONEncoder().encode(record))
        #expect(again == record)
    }

    @Test func boardStoreKeepsOriginalFileBeforeMigration() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ThoughtsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let board = folder.appendingPathComponent("board.json")
        let legacy = #"{"workspaces":[],"cardsByWorkspace":{"1":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","position":[0,0],"size":[104,104],"text":"hi"}]}}"#
        try Data(legacy.utf8).write(to: board)

        let loaded = BoardStore(fileURL: board).load()
        #expect(loaded.cardsByWorkspace[1]?.first?.text == "hi")
        let copies = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Backups").path)
        #expect(copies.count == 1)
        #expect(copies.first?.hasPrefix("before-markdown-") == true)
    }
}
