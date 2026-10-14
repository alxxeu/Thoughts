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

    private func normalized(_ text: String, cursor: Int) -> (text: String, cursor: Int) {
        let result = MarkdownFormatting.normalizedTaskMarkers(in: text, cursor: cursor)
        let ns = NSMutableString(string: text)
        for edit in result.edits { ns.replaceCharacters(in: edit.range, with: edit.marker) }
        return (ns as String, result.cursor)
    }

    @Test func taskMarkersBecomeStandard() {
        // Курсор сразу после только что набранного `[] ` — остаётся после маркера.
        #expect(normalized("[] ", cursor: 3) == ("- [ ] ", 6))
        // Несколько маркеров до курсора: сдвиг накапливается.
        let text = "[] a\n[x] b\n- [] c"
        let result = normalized(text, cursor: (text as NSString).length)
        #expect(result.text == "- [ ] a\n- [x] b\n- [ ] c")
        #expect(result.cursor == (result.text as NSString).length)
        // Курсор перед маркерами не сдвигается.
        #expect(normalized("x\n[] a", cursor: 1).cursor == 1)
        // Стандартные маркеры не трогаются.
        #expect(MarkdownFormatting.normalizedTaskMarkers(in: "- [ ] a\n- [x] b", cursor: 0).edits.isEmpty)
    }
}

