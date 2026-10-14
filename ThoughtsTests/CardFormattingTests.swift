import AppKit
import Testing
@testable import Thoughts

@MainActor
struct CardFormattingTests {
    /// Карточка с разделителем раньше не архивировалась вовсе — и теряла
    /// всё форматирование (см. DividerAttachment.supportsSecureCoding).
    @Test func formattingWithDividerSurvivesArchive() throws {
        let original = NSMutableAttributedString(string: "Bold", attributes: [.font: NSFont.boldSystemFont(ofSize: 15)])
        original.append(NSAttributedString(attachment: DividerAttachment()))
        original.append(NSAttributedString(string: "after"))

        let data = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true)
        let restored = try #require(try NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data))

        #expect(restored.string == original.string)
        #expect(restored.attribute(.attachment, at: 4, effectiveRange: nil) is DividerAttachment)
        let font = try #require(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }
}
