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

    /// Тап по задаче в ленте iPhone: `[ ]` ↔ `[x]`, остальное не трогается.
    @Test func togglingTask() {
        let text = "Shopping\n- [ ] Oat milk\n- [x] Bread"
        let lines = MarkdownStyler.parse(text)
        let checked = MarkdownFormatting.togglingTask(in: text, paragraph: lines[1])
        #expect(checked == "Shopping\n- [x] Oat milk\n- [x] Bread")
        let unchecked = MarkdownFormatting.togglingTask(in: text, paragraph: lines[2])
        #expect(unchecked == "Shopping\n- [ ] Oat milk\n- [ ] Bread")
        #expect(MarkdownFormatting.togglingTask(in: text, paragraph: lines[0]) == nil)
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

    /// Блок кода: строки выделения в ``` и обратно; пустая строка — пустой блок с курсором внутри.
    @Test func codeBlockWrapsAndUnwrapsLines() {
        let text = "intro\nlet a = 1\nlet b = 2\noutro" as NSString
        let selection = text.range(of: "a = 1\nlet b")
        let wrap = MarkdownFormatting.toggleCodeBlock(in: text, selection: selection)
        let wrapped = text.replacingCharacters(in: wrap.range, with: wrap.replacement) as NSString
        #expect(wrapped as String == "intro\n```\nlet a = 1\nlet b = 2\n```\noutro")
        #expect(wrapped.substring(with: wrap.selection) == "a = 1\nlet b")

        let unwrap = MarkdownFormatting.toggleCodeBlock(in: wrapped, selection: wrap.selection)
        let unwrapped = wrapped.replacingCharacters(in: unwrap.range, with: unwrap.replacement) as NSString
        #expect(unwrapped as String == text as String)
        #expect(unwrapped.substring(with: unwrap.selection) == "a = 1\nlet b")

        let empty = "a\n\nb" as NSString
        let cursor = MarkdownFormatting.toggleCodeBlock(in: empty, selection: NSRange(location: 2, length: 0))
        #expect(empty.replacingCharacters(in: cursor.range, with: cursor.replacement) == "a\n```\n\n```\nb")
        #expect(cursor.selection == NSRange(location: 6, length: 0))
    }
}
