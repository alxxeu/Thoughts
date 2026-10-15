import AppKit

/// Всё, что рисуется вокруг Markdown-текста карточки, и попадание кликов в
/// это нарисованное: поля блоков кода и цитат, линии разделителей,
/// квадратики чек-листов, значки в углу полей. Строки отмечает
/// MarkdownRenderer (dividerKey, quoteKey, codeBlockKey, taskBoxKey);
/// редактор (CardNSTextView) создаёт декоратор на время отрисовки или клика,
/// сам хранит состояние и сам применяет правки.
struct MarkdownBlockDecorator {
    let layoutManager: NSLayoutManager
    let textContainer: NSTextContainer
    let textStorage: NSTextStorage
    /// textContainerOrigin редактора.
    let origin: NSPoint
    /// Цвет текста карточки (цвет каретки — см. CardNSTextView.draw).
    let textColor: NSColor
    let lineColor: NSColor
    /// Блок кода, только что скопированный кнопкой, — на нём галочка.
    var copiedBlockLocation: Int?

    enum Hit {
        /// Значок копирования блока кода: текст блока без строк ```.
        case copyCode(block: NSRange, text: String)
        /// Квадратик чек-листа: что заменить внутри скобок.
        case toggleTask(range: NSRange, replacement: String)
    }

    // MARK: - Под текстом

    /// Подложка блоков кода, поле цитаты с полосой слева.
    func drawBackground() {
        for (_, box) in blockBoxes(MarkdownRenderer.codeBlockKey) {
            lineColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        }

        let accent = NSColor.controlAccentColor
        for (_, box) in blockBoxes(MarkdownRenderer.quoteKey, textPadding: 8) {
            let shape = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
            accent.withAlphaComponent(0.14).setFill()
            shape.fill()
            // Сплошная полоса по левому краю — внутри скругления поля.
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            accent.setFill()
            NSRect(x: box.minX, y: box.minY, width: 3, height: box.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: - Поверх текста

    /// Линии разделителей, квадратики чек-листов, значки в углу полей.
    func drawOverlays() {
        let fullRange = NSRange(location: 0, length: textStorage.length)

        // Линия — по СВЕЖЕМУ line fragment rect, без риска нарисовать по
        // устаревшему layout.
        textStorage.enumerateAttribute(MarkdownRenderer.dividerKey, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let y = (origin.y + lineRect.midY).rounded()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: origin.x, y: y))
            path.line(to: NSPoint(x: origin.x + textContainer.size.width, y: y))
            path.lineWidth = 1
            lineColor.setStroke()
            path.stroke()
        }

        // Квадратики чек-листов — слева, на отступе строки.
        textStorage.enumerateAttribute(MarkdownRenderer.taskBoxKey, in: fullRange) { value, range, _ in
            guard let done = value as? Bool, let box = taskBoxRect(for: range) else { return }
            let path = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
            if done {
                textColor.withAlphaComponent(0.55).setFill()
                path.fill()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: box.minX + box.width * 0.25, y: box.midY))
                check.line(to: NSPoint(x: box.minX + box.width * 0.43, y: box.maxY - box.height * 0.27))
                check.line(to: NSPoint(x: box.maxX - box.width * 0.22, y: box.minY + box.height * 0.28))
                check.lineWidth = 1.6
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                // Галочка контрастна заливке: на светлом тексте — тёмная, на тёмном — светлая.
                let isLight = (textColor.usingColorSpace(.sRGB)?.brightnessComponent ?? 1) > 0.5
                (isLight ? NSColor.black : NSColor.white).withAlphaComponent(0.8).setStroke()
                check.stroke()
            } else {
                path.lineWidth = 1.2
                textColor.withAlphaComponent(0.6).setStroke()
                path.stroke()
            }
        }

        // Значки в углу полей, оба серые: « у цитаты, копирование у кода.
        let iconColor = textColor.withAlphaComponent(0.7)
        for (_, box) in blockBoxes(MarkdownRenderer.quoteKey, textPadding: 8) {
            drawSymbol("quote.closing", color: iconColor, in: cornerIconRect(in: box))
        }
        for (block, box) in blockBoxes(MarkdownRenderer.codeBlockKey) {
            let copied = copiedBlockLocation == block.location
            drawSymbol(copied ? "checkmark" : "doc.on.doc", color: iconColor, in: cornerIconRect(in: box))
        }
    }

    // MARK: - Клики

    /// Во что попал клик (в координатах редактора), если в нарисованное.
    func hit(at point: NSPoint) -> Hit? {
        if let (block, _) = blockBoxes(MarkdownRenderer.codeBlockKey)
            .first(where: { cornerIconRect(in: $0.rect).insetBy(dx: -4, dy: -4).contains(point) }) {
            return .copyCode(block: block, text: codeContent(of: block))
        }

        var hit: Hit?
        textStorage.enumerateAttribute(MarkdownRenderer.taskBoxKey, in: NSRange(location: 0, length: textStorage.length)) { value, space, stop in
            guard value != nil, let box = taskBoxRect(for: space), box.insetBy(dx: -3, dy: -3).contains(point) else { return }
            // Содержимое скобок перед пробелом: `[ ]` ↔ `[x]`.
            let ns = textStorage.string as NSString
            let close = space.location - 1
            var open = close - 1
            while open > 0, ns.character(at: open) != 0x5B { open -= 1 } // "["
            let inside = NSRange(location: open + 1, length: close - open - 1)
            let isDone = ns.substring(with: inside).lowercased() == "x"
            hit = .toggleTask(range: inside, replacement: isDone ? " " : "x")
            stop.pointee = true
        }
        return hit
    }

    // MARK: - Геометрия

    /// Поля блоков на всю ширину. Код — по строкам целиком (узкие строки ```
    /// и есть его поля); цитата — по самому тексту плюс `textPadding` сверху
    /// и снизу: отступ перед первым абзацем TextKit не учитывает, и без
    /// этого поле цитаты в начале карточки упиралось в текст.
    private func blockBoxes(_ key: NSAttributedString.Key, textPadding: CGFloat? = nil) -> [(range: NSRange, rect: NSRect)] {
        guard textStorage.length > 0 else { return [] }
        var boxes: [(NSRange, NSRect)] = []
        var seen = Set<Int>()
        textStorage.enumerateAttribute(key, in: NSRange(location: 0, length: textStorage.length)) { value, _, _ in
            guard let block = (value as? NSValue)?.rangeValue, seen.insert(block.location).inserted else { return }
            var rect = NSRect.null
            let glyphs = layoutManager.glyphRange(forCharacterRange: block, actualCharacterRange: nil)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, lineGlyphs, _ in
                guard textPadding != nil else {
                    rect = rect.union(lineRect)
                    return
                }
                // Только сами буквы: от верха (ascender) до низа (descender)
                // шрифта строки — без отступов абзаца и межстрочного интервала.
                // Первый видимый символ: у скрытого `> ` крохотный шрифт.
                var glyph = lineGlyphs.location
                while glyph < NSMaxRange(lineGlyphs) - 1,
                      textStorage.attribute(MarkdownRenderer.hiddenKey, at: layoutManager.characterIndexForGlyph(at: glyph), effectiveRange: nil) != nil {
                    glyph += 1
                }
                let char = layoutManager.characterIndexForGlyph(at: glyph)
                let font = textStorage.attribute(.font, at: min(char, textStorage.length - 1), effectiveRange: nil) as? NSFont
                    ?? .systemFont(ofSize: 15)
                let baseline = lineRect.minY + layoutManager.location(forGlyphAt: glyph).y
                rect = rect.union(NSRect(x: lineRect.minX, y: baseline - font.ascender, width: lineRect.width, height: font.ascender - font.descender))
            }
            guard !rect.isNull else { return }
            if let textPadding { rect = rect.insetBy(dx: 0, dy: -textPadding) }
            // Незакрытый блок кода: снизу нет строки ``` — добавляем поле.
            if key == MarkdownRenderer.codeBlockKey {
                let lines = (textStorage.string as NSString).substring(with: block).components(separatedBy: "\n")
                let isClosed = lines.count > 1 && lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true
                if !isClosed { rect.size.height += 8 }
            }
            rect.origin.x = origin.x - 6
            rect.size.width = textContainer.size.width + 12
            rect.origin.y += origin.y
            boxes.append((block, rect))
        }
        return boxes
    }

    /// Квадрат чек-листа на отступе строки, по центру строчных букв.
    private func taskBoxRect(for range: NSRange) -> NSRect? {
        guard range.location < textStorage.length else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = layoutManager.location(forGlyphAt: glyph).y
        let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 15)
        let side = (font.capHeight * 1.35).rounded()
        let centerY = origin.y + line.minY + baseline - font.xHeight / 2
        return NSRect(x: origin.x + 1, y: centerY - side / 2, width: side, height: side)
    }

    /// Кнопка/значок в правом верхнем углу поля блока.
    private func cornerIconRect(in box: NSRect) -> NSRect {
        NSRect(x: box.maxX - 22, y: box.minY + 6, width: 14, height: 14)
    }

    /// Иконка SF Symbols одного цвета, в собственных пропорциях символа по
    /// центру `rect` (растягивание в квадрат сплющивало кавычки).
    private func drawSymbol(_ name: String, color: NSColor, in rect: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let size = image.size
        image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    }

    /// Текст блока кода без строк ```.
    private func codeContent(of block: NSRange) -> String {
        var lines = (textStorage.string as NSString).substring(with: block).components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true { lines.removeFirst() }
        if lines.count > 0, lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}
