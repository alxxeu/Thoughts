import Foundation
import Testing
@testable import Thoughts

/// Живой Markdown iPhone: скрытые символы, курсор, Backspace, продолжение списков.
@MainActor
struct LiveMarkdownTests {
    private func atoms(_ text: String) -> [LiveMarkdown.Atom] {
        LiveMarkdown.atoms(MarkdownStyler.parse(text), length: (text as NSString).length)
    }

    @Test func hiddenRangesCoverMarkersButNotTaskSpace() {
        let text = "# Title\n- [ ] milk\nsome **bold**"
        let hidden = LiveMarkdown.hiddenRanges(MarkdownStyler.parse(text)).map { (text as NSString).substring(with: $0) }
        #expect(hidden.contains("# "))
        #expect(hidden.contains("- [ ]")) // пробел после — видимый, на нём квадратик
        #expect(hidden.filter { $0 == "**" }.count == 2)
    }

    @Test func cursorSnapsOutOfMarkers() {
        let text = "# Title\nsome **bold** end"
        let all = atoms(text)
        // Начало строки заголовка — за `# `.
        #expect(LiveMarkdown.snap(0, atoms: all) == 2)
        #expect(LiveMarkdown.snap(1, atoms: all) == 2)
        let ns = text as NSString
        let open = ns.range(of: "**").location
        // Между звёздочками открывающих — к тексту (за них).
        #expect(LiveMarkdown.snap(open + 1, atoms: all) == open + 2)
        let close = ns.range(of: "**", options: .backwards).location
        // Между звёздочками закрывающих — к тексту (перед ними).
        #expect(LiveMarkdown.snap(close + 1, atoms: all) == close)
        // Обычная позиция не трогается.
        #expect(LiveMarkdown.snap(open, atoms: all) == open)
    }

    @Test func cursorSkipsCodeFences() {
        let text = "a\n```\ncode\n```\nb"
        let all = atoms(text)
        #expect(LiveMarkdown.snap(3, atoms: all) == 6) // открывающая ``` → начало кода
        #expect(LiveMarkdown.snap(12, atoms: all) == 10) // закрывающая ``` → конец кода
    }

    @Test func backspaceRemovesBlockMarkerAndLastLetterSpan() {
        // Сразу за `# ` — снять заголовок.
        #expect(LiveMarkdown.backspaceRange(at: 2, text: "# Title") == NSRange(location: 0, length: 2))
        // За скрытыми `**` — стереть видимую букву перед ними.
        let text = "x **ab** y"
        let afterBold = (text as NSString).range(of: "** y").location + 2
        #expect(LiveMarkdown.backspaceRange(at: afterBold, text: text) == NSRange(location: 5, length: 1))
        // Последняя буква фрагмента — фрагмент целиком.
        let single = "x **a** y"
        let afterSingle = (single as NSString).range(of: "** y").location + 2
        #expect(LiveMarkdown.backspaceRange(at: afterSingle, text: single) == NSRange(location: 2, length: 5))
        // Обычная буква — обычное поведение.
        #expect(LiveMarkdown.backspaceRange(at: 1, text: "ab") == nil)
    }

    @Test func returnContinuesAndEndsLists() {
        let bullet = "- milk"
        let next = LiveMarkdown.newline(at: 6, text: bullet)
        #expect(next?.replacement == "\n- ")
        let task = LiveMarkdown.newline(at: 10, text: "- [x] milk")
        #expect(task?.replacement == "\n- [ ] ")
        let numbered = LiveMarkdown.newline(at: 6, text: "2. one")
        #expect(numbered?.replacement == "\n3. ")
        // Пустой пункт — Return снимает маркер.
        let empty = LiveMarkdown.newline(at: 8, text: "a\n- [ ] ")
        #expect(empty?.range == NSRange(location: 2, length: 6))
        #expect(empty?.replacement == "")
        #expect(LiveMarkdown.newline(at: 5, text: "plain") == nil)
    }

    /// Второй Return в блоке кода выходит из него; первый — обычный перевод строки.
    @Test func doubleReturnExitsCodeBlock() {
        func apply(_ text: String, _ edit: MarkdownFormatting.Edit?) -> (String, Int)? {
            guard let edit else { return nil }
            return ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selection.location)
        }
        // Строка кода не пустая — обычный Return.
        #expect(LiveMarkdown.newline(at: 8, text: "```\nlet\n```") == nil)
        // Закрытый блок в конце текста.
        let closed = "```\nlet\n\n```"
        let r1 = apply(closed, LiveMarkdown.newline(at: 8, text: closed))
        #expect(r1?.0 == "```\nlet\n```\n")
        #expect(r1?.1 == 12)
        // За блоком есть текст — курсор в его начало.
        let after = "```\nlet\n\n```\nnext"
        let r2 = apply(after, LiveMarkdown.newline(at: 8, text: after))
        #expect(r2?.0 == "```\nlet\n```\nnext")
        #expect(r2?.1 == 12)
        // Незакрытый блок — дописать ```.
        let open = "```\nlet\n"
        let r3 = apply(open, LiveMarkdown.newline(at: 8, text: open))
        #expect(r3?.0 == "```\nlet\n```\n")
        #expect(r3?.1 == 12)
        // Пустая первая строка нового блока — не выход.
        #expect(LiveMarkdown.newline(at: 4, text: "```\n\n```") == nil)
    }

    /// Backspace на пустой строке цитаты под цитатой — в конец строки выше; одиночную — снять.
    @Test func backspaceOnEmptyQuoteLineJoinsPreviousQuoteLine() {
        let text = "> one\n> "
        let range = LiveMarkdown.backspaceRange(at: 8, text: text)
        #expect(range == NSRange(location: 5, length: 3))
        #expect((text as NSString).replacingCharacters(in: range!, with: "") == "> one")
        // Одна пустая цитата — снимается только маркер.
        #expect(LiveMarkdown.backspaceRange(at: 2, text: "> ") == NSRange(location: 0, length: 2))
        // Непустая строка цитаты в начале — снять маркер, как раньше.
        #expect(LiveMarkdown.backspaceRange(at: 8, text: "> one\n> two") == NSRange(location: 6, length: 2))
    }

    @Test func columnBreakIsHiddenAndSkipped() {
        let text = "a\n||\nb"
        let paragraphs = MarkdownStyler.parse(text)
        #expect(LiveMarkdown.hiddenRanges(paragraphs).contains(NSRange(location: 2, length: 2)))
        // Курсор внутри `||` или перед ней — на начало следующей колонки.
        #expect(LiveMarkdown.snap(2, atoms: LiveMarkdown.atoms(paragraphs, length: 6)) == 5)
        #expect(LiveMarkdown.snap(3, atoms: LiveMarkdown.atoms(paragraphs, length: 6)) == 5)
        // Только что набранная `||` в конце текста — выйти из неё можно.
        #expect(LiveMarkdown.atoms(MarkdownStyler.parse("a\n||"), length: 4).isEmpty)
        // Backspace в начале колонки убирает `||` целиком, с переводом строки.
        #expect(LiveMarkdown.backspaceRange(at: 5, text: text) == NSRange(location: 2, length: 3))
    }
}
