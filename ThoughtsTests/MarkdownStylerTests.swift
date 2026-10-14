import Foundation
import Testing
@testable import Thoughts

@MainActor
struct MarkdownStylerTests {
    /// Подстроки, к которым применён стиль, — читать проще, чем NSRange.
    private func styled(_ text: String, _ style: MarkdownStyler.Inline) -> [String] {
        let ns = text as NSString
        return MarkdownStyler.parse(text).flatMap(\.inlines)
            .filter { $0.style == style }
            .map { ns.substring(with: $0.range) }
    }

    private func markers(_ text: String) -> [String] {
        let ns = text as NSString
        return MarkdownStyler.parse(text).flatMap(\.markers).map { ns.substring(with: $0) }
    }

    @Test func inlineStyles() {
        let text = "a **bold** *it* ~~del~~ ~under~ ==mark== `co*de*` b"
        #expect(styled(text, .bold) == ["bold"])
        #expect(styled(text, .italic) == ["it"])
        #expect(styled(text, .strikethrough) == ["del"])
        #expect(styled(text, .underline) == ["under"])
        #expect(styled(text, .highlight) == ["mark"])
        // Внутри кода разметки нет.
        #expect(styled(text, .code) == ["co*de*"])
    }

    @Test func boldItalicTogether() {
        #expect(styled("***both***", .bold) == ["*both*"])
        #expect(styled("***both***", .italic) == ["both"])
        #expect(markers("***both***").count == 4)
    }

    @Test func unclosedAndSpacedMarkersStayText() {
        #expect(MarkdownStyler.parse("**open").flatMap(\.inlines).isEmpty)
        #expect(MarkdownStyler.parse("a * b * c").flatMap(\.inlines).isEmpty)
        #expect(MarkdownStyler.parse("a = b").flatMap(\.inlines).isEmpty)
        #expect(MarkdownStyler.parse("**open").flatMap(\.markers).isEmpty)
    }

    @Test func escapedCharactersAreLiteral() {
        let text = #"2\*3\*4"#
        #expect(MarkdownStyler.parse(text).flatMap(\.inlines).isEmpty)
        #expect(markers(text) == [#"\"#, #"\"#])
        #expect(MarkdownStyler.plainText(text) == "2*3*4")
    }

    @Test func linkHidesUrlAndKeepsInnerStyle() {
        let text = "see [**docs**](https://example.com) now"
        let link = MarkdownStyler.parse(text).flatMap(\.inlines).first { if case .link = $0.style { true } else { false } }
        #expect(link?.style == .link("https://example.com"))
        #expect(styled(text, .bold) == ["docs"])
        #expect(MarkdownStyler.plainText(text) == "see docs now")
    }

    @Test func blocks() {
        let paragraphs = MarkdownStyler.parse("# Title\n### Small\n- item\n12. step\n---\nplain")
        #expect(paragraphs.map(\.block) == [.heading(1), .heading(3), .bullet, .numbered, .divider, .paragraph])
        #expect(paragraphs[0].blockMarker == NSRange(location: 0, length: 2))
        #expect(paragraphs[3].blockMarker == nil)
        // Разделитель — от 2 до 10 дефисов.
        #expect(MarkdownStyler.parse("--\n----------\n-\n-----------\n - - ").map(\.block) == [.divider, .divider, .paragraph, .paragraph, .paragraph])
        // #### — уже не заголовок.
        #expect(MarkdownStyler.parse("#### x")[0].block == .paragraph)
    }

    @Test func rangesAreUTF16AndPerLine() {
        let text = "🐼 **a**\n**b"
        let paragraphs = MarkdownStyler.parse(text)
        #expect(paragraphs.count == 2)
        #expect(styled(text, .bold) == ["a"])
        // Маркер не перешагивает через перевод строки.
        #expect(paragraphs[1].inlines.isEmpty)
    }

    @Test func plainTextForSpotlight() {
        let text = "# Plan\n- **buy** milk\n---\n~~old~~ ==new=="
        #expect(MarkdownStyler.plainText(text) == "Plan\n\u{2022} buy milk\n\nold new")
    }

    @Test func emptyAndTrailingNewline() {
        #expect(MarkdownStyler.parse("").count == 1)
        #expect(MarkdownStyler.parse("a\n").count == 2)
        #expect(MarkdownStyler.plainText("a\n") == "a\n")
    }
}
