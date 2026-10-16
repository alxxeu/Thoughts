import UIKit

/// Вёрстка редактора iPhone (TextKit 1) — порт Mac `MarkdownBlockDecorator` и
/// `MarkdownBulletGlyphs`: `-` рисуется как `•`, под текстом — подложки блоков
/// кода и поле цитаты с полосой, поверх — линии `---` и квадратики чек-листов.
/// Строки отмечает LiveMarkdownStyler; текст не меняется.
final class LiveLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var textColor: UIColor { LiveMarkdownStyler.color }

    // MARK: - `-` → `•`

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: UIFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        let count = glyphRange.length
        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: count))
        var changed = false
        for i in 0..<count {
            let index = charIndexes[i]
            guard index < storage.length,
                  storage.attribute(LiveMarkdownStyler.bulletKey, at: index, effectiveRange: nil) != nil,
                  let bullet = Self.bulletGlyph(in: aFont) else { continue }
            newGlyphs[i] = bullet
            changed = true
        }
        guard changed else { return 0 } // 0 — глифы ставятся как обычно
        layoutManager.setGlyphs(newGlyphs, properties: props, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        return count
    }

    private static func bulletGlyph(in font: UIFont) -> CGGlyph? {
        var character: UniChar = 0x2022
        var glyph: CGGlyph = 0
        return CTFontGetGlyphsForCharacters(font as CTFont, &character, &glyph, 1) ? glyph : nil
    }

    // MARK: - Под текстом

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        for (_, box) in blockBoxes(LiveMarkdownStyler.codeBlockKey, origin: origin) {
            UIColor(white: 1, alpha: 0.07).setFill()
            UIBezierPath(roundedRect: box, cornerRadius: 8).fill()
        }
        for (_, box) in blockBoxes(LiveMarkdownStyler.quoteKey, origin: origin, textPadding: 6) {
            let shape = UIBezierPath(roundedRect: box, cornerRadius: 8)
            LiveMarkdownStyler.accent.withAlphaComponent(0.14).setFill()
            shape.fill()
            guard let context = UIGraphicsGetCurrentContext() else { continue }
            context.saveGState()
            shape.addClip()
            LiveMarkdownStyler.accent.setFill()
            UIRectFill(CGRect(x: box.minX, y: box.minY, width: 3, height: box.height))
            context.restoreGState()
        }
    }

    // MARK: - Поверх текста

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let full = NSRange(location: 0, length: storage.length)

        storage.enumerateAttribute(LiveMarkdownStyler.dividerKey, in: full) { value, range, _ in
            guard value != nil else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let line = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let y = (origin.y + line.midY).rounded() + 0.5
            let path = UIBezierPath()
            path.move(to: CGPoint(x: origin.x, y: y))
            path.addLine(to: CGPoint(x: origin.x + container.size.width - container.lineFragmentPadding * 2, y: y))
            path.lineWidth = 1
            textColor.withAlphaComponent(0.25).setStroke()
            path.stroke()
        }

        storage.enumerateAttribute(LiveMarkdownStyler.taskBoxKey, in: full) { value, range, _ in
            guard let done = value as? Bool, let box = taskBoxRect(for: range, origin: origin) else { return }
            let path = UIBezierPath(roundedRect: box, cornerRadius: 4)
            if done {
                LiveMarkdownStyler.accent.setFill()
                path.fill()
                let check = UIBezierPath()
                check.move(to: CGPoint(x: box.minX + box.width * 0.25, y: box.midY))
                check.addLine(to: CGPoint(x: box.minX + box.width * 0.43, y: box.maxY - box.height * 0.28))
                check.addLine(to: CGPoint(x: box.maxX - box.width * 0.22, y: box.minY + box.height * 0.28))
                check.lineWidth = 1.8
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                UIColor.white.setStroke()
                check.stroke()
            } else {
                path.lineWidth = 1.4
                textColor.withAlphaComponent(0.6).setStroke()
                path.stroke()
            }
        }
    }

    // MARK: - Касания

    /// Касание квадратика чек-листа (в координатах текста): что заменить внутри скобок.
    func taskToggle(at point: CGPoint, origin: CGPoint) -> MarkdownFormatting.Edit? {
        guard let storage = textStorage else { return nil }
        var edit: MarkdownFormatting.Edit?
        storage.enumerateAttribute(LiveMarkdownStyler.taskBoxKey, in: NSRange(location: 0, length: storage.length)) { value, space, stop in
            guard value != nil, let box = taskBoxRect(for: space, origin: origin),
                  box.insetBy(dx: -10, dy: -10).contains(point) else { return }
            let ns = storage.string as NSString
            let close = space.location - 1
            var open = close - 1
            while open > 0, ns.character(at: open) != 0x5B { open -= 1 } // "["
            let inside = NSRange(location: open + 1, length: close - open - 1)
            let isDone = ns.substring(with: inside).lowercased() == "x"
            edit = MarkdownFormatting.Edit(range: inside, replacement: isDone ? " " : "x", selection: NSRange(location: NSMaxRange(space), length: 0))
            stop.pointee = true
        }
        return edit
    }

    // MARK: - Геометрия

    /// Поля блоков на всю ширину. Код — по строкам целиком (узкие строки ``` и
    /// есть его поля); цитата — по самим буквам плюс `textPadding` сверху и снизу.
    private func blockBoxes(_ key: NSAttributedString.Key, origin: CGPoint, textPadding: CGFloat? = nil) -> [(range: NSRange, rect: CGRect)] {
        guard let storage = textStorage, let container = textContainers.first, storage.length > 0 else { return [] }
        var boxes: [(NSRange, CGRect)] = []
        var seen = Set<Int>()
        storage.enumerateAttribute(key, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let block = (value as? NSValue)?.rangeValue, seen.insert(block.location).inserted,
                  NSMaxRange(block) <= storage.length else { return }
            var rect = CGRect.null
            let glyphs = glyphRange(forCharacterRange: block, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, lineGlyphs, _ in
                guard textPadding != nil else {
                    rect = rect.union(lineRect)
                    return
                }
                // Скрытый `> ` — шрифтом строки, по первому глифу и меряем.
                let glyph = lineGlyphs.location
                let char = min(self.characterIndexForGlyph(at: glyph), storage.length - 1)
                let font = storage.attribute(.font, at: char, effectiveRange: nil) as? UIFont ?? LiveMarkdownStyler.font
                let baseline = lineRect.minY + self.location(forGlyphAt: glyph).y
                rect = rect.union(CGRect(x: lineRect.minX, y: baseline - font.ascender, width: lineRect.width, height: font.ascender - font.descender))
            }
            guard !rect.isNull else { return }
            if let textPadding { rect = rect.insetBy(dx: 0, dy: -textPadding) }
            rect.origin.x = origin.x - 6
            rect.size.width = container.size.width + 12
            rect.origin.y += origin.y
            boxes.append((block, rect))
        }
        return boxes
    }

    /// Квадрат чек-листа на отступе строки, по центру строчных букв.
    private func taskBoxRect(for range: NSRange, origin: CGPoint) -> CGRect? {
        guard let storage = textStorage, range.location < storage.length else { return nil }
        let glyph = glyphIndexForCharacter(at: range.location)
        let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = location(forGlyphAt: glyph).y
        let font = LiveMarkdownStyler.font
        let side = (font.capHeight * 1.45).rounded()
        let centerY = origin.y + line.minY + baseline - font.xHeight / 2
        return CGRect(x: origin.x + 1, y: centerY - side / 2, width: side, height: side)
    }
}
