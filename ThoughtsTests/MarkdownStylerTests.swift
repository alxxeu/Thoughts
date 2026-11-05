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

    @Test func quoteNeedsSpaceAfterMarker() {
        // Одинокий `>` и `>text` — обычный текст; `>` внутри цитаты — её пустая строка.
        #expect(MarkdownStyler.parse(">").map(\.block) == [.paragraph])
        #expect(MarkdownStyler.parse(">the").map(\.block) == [.paragraph])
        #expect(MarkdownStyler.parse("> ").map(\.block) == [.quote])
        #expect(MarkdownStyler.parse("a\n>").map(\.block) == [.paragraph, .paragraph])
        #expect(MarkdownStyler.parse("> a\n>").map(\.block) == [.quote, .quote])
    }

    @Test func quotesAndTasks() {
        let paragraphs = MarkdownStyler.parse("> said **this**\n>\n- [ ] todo\n- [x] done\n- [ ]no space\n[] a\n[x] b\n[ ] c\n- [] d")
        #expect(paragraphs.map(\.block) == [.quote, .quote, .task(done: false), .task(done: true), .bullet,
                                            .task(done: false), .task(done: true), .task(done: false), .task(done: false)])
        #expect(paragraphs[0].blockMarker == NSRange(location: 0, length: 2))
        #expect(paragraphs[1].blockMarker?.length == 1)
        #expect(paragraphs[2].blockMarker?.length == 6)
        #expect(paragraphs[5].blockMarker?.length == 3)
        #expect(paragraphs[6].blockMarker?.length == 4)
        // Соседние строки цитаты — один блок.
        #expect(paragraphs[0].quoteBlock == paragraphs[1].quoteBlock)
        #expect(paragraphs[0].quoteBlock == NSRange(location: 0, length: 17))
        #expect(paragraphs[2].quoteBlock == nil)
        // Внутри цитаты разметка работает.
        #expect(styled("> said **this**", .bold) == ["this"])
    }

    @Test func codeBlocks() {
        let text = "a\n```swift\nlet **x** = 1\n```\nb **c**"
        let paragraphs = MarkdownStyler.parse(text)
        #expect(paragraphs.map(\.block) == [.paragraph, .codeFence, .code, .codeFence, .paragraph])
        // Внутри блока кода разметки нет, после него — снова есть.
        #expect(paragraphs[2].inlines.isEmpty)
        #expect(styled(text, .bold) == ["c"])
        let block = (text as NSString).range(of: "```swift\nlet **x** = 1\n```")
        #expect(paragraphs[1].codeBlock == block)
        #expect(paragraphs[3].codeBlock == block)
        #expect(paragraphs[0].codeBlock == nil)
    }

    @Test func unclosedCodeBlockRunsToEnd() {
        let paragraphs = MarkdownStyler.parse("```\n# not heading\n**x**")
        #expect(paragraphs.map(\.block) == [.codeFence, .code, .code])
    }

    @Test func plainTextForNewBlocks() {
        #expect(MarkdownStyler.plainText("> quote\n- [ ] a\n- [x] b\n```\n*raw*\n```") == "quote\n\u{2610} a\n\u{2611} b\n\n*raw*\n")
    }

    @Test func linkWithParenthesesInUrl() {
        let text = "[Swift](https://en.wikipedia.org/wiki/Swift_(language)) rocks"
        let link = MarkdownStyler.parse(text).flatMap(\.inlines).first { if case .link = $0.style { true } else { false } }
        #expect(link?.style == .link("https://en.wikipedia.org/wiki/Swift_(language)"))
        #expect(MarkdownStyler.plainText(text) == "Swift rocks")
    }

    @Test func columnBreakSplitsColumns() {
        let paragraphs = MarkdownStyler.parse("# Plan\n- [ ] a\n||\n# To go\n- [ ] b\n||\nReady")
        #expect(paragraphs.map(\.column) == [0, 0, 0, 1, 1, 1, 2])
        #expect(paragraphs.map(\.isColumnBreak) == [false, false, true, false, false, true, false])
        // `||` в блоке кода и внутри строки — не разделитель.
        #expect(MarkdownStyler.parse("```\n||\n```").allSatisfy { !$0.isColumnBreak })
        #expect(MarkdownStyler.parse("a || b").allSatisfy { !$0.isColumnBreak })
        #expect(MarkdownStyler.plainText("a\n||\nb") == "a\n\nb")
    }

    @Test func boardMarkerIsNotIndexed() {
        #expect(MarkdownStyler.plainText("::: board\n# Plan\n- a").hasPrefix("\n"))
        #expect(!MarkdownStyler.plainText("::: board\n# Plan\n- a").contains(":::"))
    }
}
