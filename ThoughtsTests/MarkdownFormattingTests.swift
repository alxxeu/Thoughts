import Foundation
import Testing
@testable import Thoughts

@MainActor
struct MarkdownFormattingTests {
    /// Применяет правку и возвращает текст и выделенную после неё строку.
    private func apply(_ marker: String, _ text: String, _ selected: String) -> (text: String, selected: String) {
        let ns = text as NSString
        let selection = selected.isEmpty ? NSRange(location: ns.length, length: 0) : ns.range(of: selected)
        let edit = MarkdownFormatting.toggle(marker, in: ns, selection: selection)
        let result = ns.replacingCharacters(in: edit.range, with: edit.replacement) as NSString
        return (result as String, result.substring(with: edit.selection))
    }

    @Test func wrapAndUnwrap() {
        let wrapped = apply("**", "make it bold", "bold")
        #expect(wrapped.text == "make it **bold**")
        #expect(wrapped.selected == "bold")
        // Повторное нажатие на то же выделение снимает разметку.
        #expect(apply("**", wrapped.text, "bold").text == "make it bold")
        // Выделены и сами звёздочки — тоже снимает.
        #expect(apply("**", "a **b** c", "**b**").text == "a b c")
    }

    @Test func italicInsideBoldIsNotConfused() {
        // ⌘I на жирном слове добавляет курсив, а не съедает звёздочку жирного.
        #expect(apply("*", "**b**", "b").text == "***b***")
        // Из жирного курсива ⌘I снимает только курсив.
        #expect(apply("*", "***b***", "b").text == "**b**")
        #expect(apply("**", "***b***", "b").text == "*b*")
    }

    @Test func emptySelectionInsertsPair() {
        let ns = "x " as NSString
        let edit = MarkdownFormatting.toggle("==", in: ns, selection: NSRange(location: 2, length: 0))
        #expect(edit.replacement == "====")
        #expect(edit.selection == NSRange(location: 4, length: 0))
    }

    @Test func spacesStayOutsideAndLinesWrapSeparately() {
        #expect(apply("~~", "a  old  b", "  old  ").text == "a  ~~old~~  b")
        #expect(apply("*", "one\n\ntwo", "one\n\ntwo").text == "*one*\n\n*two*")
    }

    @Test func typingSpaceExpandsTaskMarker() {
        #expect(MarkdownFormatting.standardTaskMarker(typingSpaceAfter: "[]") == "- [ ] ")
        #expect(MarkdownFormatting.standardTaskMarker(typingSpaceAfter: "[ ]") == "- [ ] ")
        #expect(MarkdownFormatting.standardTaskMarker(typingSpaceAfter: "- []") == "- [ ] ")
        #expect(MarkdownFormatting.standardTaskMarker(typingSpaceAfter: "[x]") == "- [x] ")
        // Уже стандартный маркер и обычный текст — не трогаем.
        #expect(MarkdownFormatting.standardTaskMarker(typingSpaceAfter: "- [ ]") == nil)
        #expect(MarkdownFormatting.standardTaskMarker(typingSpaceAfter: "a []") == nil)
        #expect(MarkdownFormatting.standardTaskMarker(typingSpaceAfter: "[] already") == nil)
    }

    @Test func pastedTaskMarkersBecomeStandard() {
        #expect(MarkdownFormatting.standardizingTaskMarkers("[] a\n[x] b\n- [ ] c", atLineStart: true) == "- [ ] a\n- [x] b\n- [ ] c")
        // Вставка посреди строки: первая строка продолжает чужую — не трогаем.
        #expect(MarkdownFormatting.standardizingTaskMarkers("[] a\n[] b", atLineStart: false) == "[] a\n- [ ] b")
    }

    // MARK: Блоки

    private func block(_ kind: MarkdownFormatting.BlockKind, _ text: String, caretAt: String? = nil, select: String? = nil) -> (text: String, selection: NSRange) {
        let ns = text as NSString
        let selection = select.map { ns.range(of: $0) } ?? NSRange(location: caretAt.map { ns.range(of: $0).location } ?? ns.length, length: 0)
        let edit = MarkdownFormatting.toggleBlock(kind, in: ns, selection: selection)
        return (ns.replacingCharacters(in: edit.range, with: edit.replacement), edit.selection)
    }

    @Test func blockMarkerAddedReplacedAndRemoved() {
        #expect(block(.heading(2), "title").text == "## title")
        #expect(block(.heading(2), "## title").text == "title")
        #expect(block(.heading(1), "## title").text == "# title")
        #expect(block(.quote, "- item").text == "> item")
        #expect(block(.task, "[x] done").text == "- [ ] done")
        #expect(block(.bullet, "- [ ] a").text == "- a")
        #expect(block(.bullet, "").text == "- ")
    }

    @Test func blockCaretStaysInLineText() {
        let added = block(.heading(1), "title", caretAt: "tle")
        #expect(added.selection == NSRange(location: 4, length: 0)) // t|itle → после «# »
        let removed = block(.heading(1), "# title", caretAt: "tle")
        #expect(removed.selection == NSRange(location: 2, length: 0))
        #expect(block(.bullet, "", caretAt: nil).selection == NSRange(location: 2, length: 0))
    }

    @Test func blockOnSeveralLines() {
        #expect(block(.numbered, "a\n\nb", select: "a\n\nb").text == "1. a\n\n2. b")
        #expect(block(.numbered, "1. a\n\n2. b", select: "1. a\n\n2. b").text == "a\n\nb")
        // Часть строк уже такого вида — ставим всем.
        #expect(block(.bullet, "- a\nb", select: "- a\nb").text == "- a\n- b")
    }

    @Test func dividerOnItsOwnLine() {
        let ns = "abc" as NSString
        let edit = MarkdownFormatting.insertDivider(in: ns, selection: NSRange(location: 3, length: 0))
        #expect(ns.replacingCharacters(in: edit.range, with: edit.replacement) == "abc\n--\n")
        let start = MarkdownFormatting.insertDivider(in: ns, selection: NSRange(location: 0, length: 0))
        #expect(ns.replacingCharacters(in: start.range, with: start.replacement) == "--\nabc")
    }

    @Test func codeBlockWrapsAndUnwraps() {
        let ns = "code" as NSString
        let wrap = MarkdownFormatting.toggleCodeBlock(in: ns, selection: NSRange(location: 0, length: 4))
        let wrapped = ns.replacingCharacters(in: wrap.range, with: wrap.replacement)
        #expect(wrapped == "```\ncode\n```")
        let unwrap = MarkdownFormatting.toggleCodeBlock(in: wrapped as NSString, selection: NSRange(location: 4, length: 4))
        #expect((wrapped as NSString).replacingCharacters(in: unwrap.range, with: unwrap.replacement) == "code")
    }
}
