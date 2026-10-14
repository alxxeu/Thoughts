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

    private func hidden(_ text: String, selection: NSRange?) -> String {
        let s = NSMutableAttributedString(string: text)
        MarkdownRenderer.style(s, typography: typography, selection: selection)
        var out = ""
        for (i, ch) in (text as NSString).description.utf16.enumerated() {
            if s.attribute(MarkdownRenderer.hiddenKey, at: i, effectiveRange: nil) != nil { out.append(Character(Unicode.Scalar(ch)!)) }
        }
        return out
    }

    @Test func markersHideAwayFromCursor() {
        let text = "a **b** c **d**"
        // Не в фокусе — скрыто всё.
        #expect(hidden(text, selection: nil) == "********")
        // Курсор сразу после первого `**b**` — его звёздочки видны.
        #expect(hidden(text, selection: NSRange(location: 7, length: 0)) == "****")
        // Курсор у пробела между словами — ни один фрагмент не касается.
        #expect(hidden(text, selection: NSRange(location: 9, length: 0)) == "********")
    }

    @Test func blockMarkers() {
        #expect(hidden("# Title", selection: NSRange(location: 3, length: 0)) == "# ")
        let list = NSMutableAttributedString(string: "- item")
        MarkdownRenderer.style(list, typography: typography)
        #expect(list.attribute(MarkdownRenderer.bulletKey, at: 0, effectiveRange: nil) != nil)
        #expect(list.attribute(MarkdownRenderer.bulletKey, at: 1, effectiveRange: nil) == nil)
        #expect(hidden("x\n---", selection: NSRange(location: 0, length: 0)) == "---")
        #expect(hidden("x\n---", selection: NSRange(location: 4, length: 0)).isEmpty)
    }
}
