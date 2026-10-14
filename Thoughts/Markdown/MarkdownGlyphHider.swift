import AppKit

/// Прячет служебные символы Markdown на уровне вёрстки: у символов с
/// MarkdownRenderer.hiddenKey глиф нулевой ширины (.null), `-` маркера списка
/// рисуется как `•`. Сам текст при этом не меняется — копирование, undo и
/// сохранение работают с исходным Markdown.
final class MarkdownGlyphHider: NSObject, NSLayoutManagerDelegate {
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        let count = glyphRange.length
        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: count))
        var newProps = Array(UnsafeBufferPointer(start: props, count: count))
        var changed = false

        for i in 0..<count {
            let index = charIndexes[i]
            guard index < storage.length else { continue }
            if storage.attribute(MarkdownRenderer.hiddenKey, at: index, effectiveRange: nil) != nil {
                newProps[i] = .null
                changed = true
            } else if storage.attribute(MarkdownRenderer.bulletKey, at: index, effectiveRange: nil) != nil,
                      let bullet = Self.bulletGlyph(in: aFont) {
                newGlyphs[i] = bullet
                changed = true
            }
        }
        // 0 — AppKit ставит глифы сам, как обычно.
        guard changed else { return 0 }
        layoutManager.setGlyphs(newGlyphs, properties: newProps, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        return count
    }

    private static func bulletGlyph(in font: NSFont) -> CGGlyph? {
        var character: UniChar = 0x2022
        var glyph: CGGlyph = 0
        return CTFontGetGlyphsForCharacters(font as CTFont, &character, &glyph, 1) ? glyph : nil
    }
}
