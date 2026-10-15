import AppKit

/// Подмена глифа на уровне вёрстки: `-` маркера списка рисуется как `•`.
/// Сам текст при этом не меняется — копирование, undo и сохранение работают
/// с исходным Markdown. (Скрытые символы — не здесь: см. MarkdownRenderer.hiddenKey.)
final class MarkdownBulletGlyphs: NSObject, NSLayoutManagerDelegate {
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
        var changed = false

        for i in 0..<count {
            let index = charIndexes[i]
            guard index < storage.length,
                  storage.attribute(MarkdownRenderer.bulletKey, at: index, effectiveRange: nil) != nil,
                  let bullet = Self.bulletGlyph(in: aFont) else { continue }
            newGlyphs[i] = bullet
            changed = true
        }
        // 0 — AppKit ставит глифы сам, как обычно.
        guard changed else { return 0 }
        layoutManager.setGlyphs(newGlyphs, properties: props, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        return count
    }

    private static func bulletGlyph(in font: NSFont) -> CGGlyph? {
        var character: UniChar = 0x2022
        var glyph: CGGlyph = 0
        return CTFontGetGlyphsForCharacters(font as CTFont, &character, &glyph, 1) ? glyph : nil
    }
}
