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
}
