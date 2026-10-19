import AppKit
import Testing
@testable import Thoughts

@MainActor
struct MarkdownRendererTests {
    private let typography = CardTypography(font: .systemFont(ofSize: 15), color: .white)

    private func styled(_ text: String) -> NSMutableAttributedString {
        let s = NSMutableAttributedString(string: text)
        MarkdownRenderer.style(s, typography: typography)
        return s
    }

    @Test func boldTextAndDimMarkers() {
        let s = styled("a **bold** b")
        let font = s.attribute(.font, at: 4, effectiveRange: nil) as? NSFont
        #expect(font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true)
        let marker = s.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        #expect(marker?.alphaComponent ?? 1 < 0.5)
        let plain = s.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(plain?.alphaComponent == 1)
    }

    @Test func linksAndBareUrls() {
        let s = styled("[docs](https://docs.com) and https://site.com/~me")
        #expect((s.attribute(.link, at: 1, effectiveRange: nil) as? URL)?.absoluteString == "https://docs.com")
        let bare = ("[docs](https://docs.com) and https://site.com/~me" as NSString).range(of: "https://site.com")
        #expect(s.attribute(.link, at: bare.location + 2, effectiveRange: nil) != nil)
    }

    @Test func headingAndDivider() {
        let s = styled("# Title\n---\nx")
        let font = s.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        #expect((font?.pointSize ?? 0) > 15)
        #expect(s.attribute(MarkdownRenderer.dividerKey, at: 9, effectiveRange: nil) != nil)
        #expect(s.attribute(MarkdownRenderer.dividerKey, at: 12, effectiveRange: nil) == nil)
    }

    @Test func restyleDropsStaleStyles() {
        let s = styled("**x**")
        s.replaceCharacters(in: NSRange(location: 0, length: 2), with: "")
        MarkdownRenderer.style(s, typography: typography)
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == false)
    }

    private func hidden(_ text: String) -> String {
        let s = NSMutableAttributedString(string: text)
        MarkdownRenderer.style(s, typography: typography)
        var out = ""
        for (i, ch) in (text as NSString).description.utf16.enumerated() {
            if s.attribute(MarkdownRenderer.hiddenKey, at: i, effectiveRange: nil) != nil { out.append(Character(Unicode.Scalar(ch)!)) }
        }
        return out
    }

    @Test func markersAlwaysHidden() {
        // Скрыто всё, где бы ни стоял курсор (живой Markdown, как на iPhone).
        #expect(hidden("a **b** c **d**") == "********")
    }

    @Test func blockMarkers() {
        #expect(hidden("# Title") == "# ")
        let list = NSMutableAttributedString(string: "- item")
        MarkdownRenderer.style(list, typography: typography)
        #expect(list.attribute(MarkdownRenderer.bulletKey, at: 0, effectiveRange: nil) != nil)
        #expect(list.attribute(MarkdownRenderer.bulletKey, at: 1, effectiveRange: nil) == nil)
        // Разделитель не скрывается, а становится прозрачным — у строки остаётся высота.
        #expect(hidden("x\n---").isEmpty)
        let divider = NSMutableAttributedString(string: "x\n---")
        MarkdownRenderer.style(divider, typography: typography)
        #expect(divider.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor == .clear)
    }

    @Test func newBlocks() {
        // Цитата: черта, `> ` скрыт без курсора.
        #expect(hidden("> q") == "> ")
        let quote = styled("> q")
        #expect(quote.attribute(MarkdownRenderer.quoteKey, at: 2, effectiveRange: nil) != nil)

        // Чек-лист: `[x]` скрыт, пробел за ним несёт квадратик, выполненный — зачёркнут.
        let task = NSMutableAttributedString(string: "[x] done")
        MarkdownRenderer.style(task, typography: typography)
        #expect(task.attribute(MarkdownRenderer.hiddenKey, at: 0, effectiveRange: nil) != nil)
        #expect(task.attribute(MarkdownRenderer.hiddenKey, at: 3, effectiveRange: nil) == nil)
        #expect(task.attribute(MarkdownRenderer.taskBoxKey, at: 3, effectiveRange: nil) as? Bool == true)
        #expect(task.attribute(.strikethroughStyle, at: 5, effectiveRange: nil) != nil)

        // Блок кода: моноширинный, ``` прозрачны без курсора, ссылки внутри не ставятся.
        let code = styled("```\nhttps://x.com **b**\n```")
        let font = code.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        #expect(font?.isFixedPitch == true)
        #expect(code.attribute(.link, at: 6, effectiveRange: nil) == nil)
        #expect(code.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .clear)
        #expect(code.attribute(MarkdownRenderer.codeBlockKey, at: 6, effectiveRange: nil) != nil)
    }

    @Test func urlInsideHiddenLinkMarkupIsNotALink() {
        let s = styled("[site](https://example.com)")
        #expect(s.attribute(.link, at: 1, effectiveRange: nil) != nil) // текст ссылки
        #expect(s.attribute(.link, at: 10, effectiveRange: nil) == nil) // адрес в скобках
    }

    @Test func emptyFenceIsPlainText() {
        // Одиночный ``` и блок без строк кода — не блок: без поля и кнопки.
        #expect(styled("```").attribute(MarkdownRenderer.codeBlockKey, at: 0, effectiveRange: nil) == nil)
        #expect(styled("```\n```").attribute(MarkdownRenderer.codeBlockKey, at: 0, effectiveRange: nil) == nil)
        #expect(styled("```\nx").attribute(MarkdownRenderer.codeBlockKey, at: 0, effectiveRange: nil) != nil)
    }
}
