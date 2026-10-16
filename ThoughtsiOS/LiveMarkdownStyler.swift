import UIKit

/// Оформление Markdown в редакторе iPhone — порт Mac `MarkdownRenderer` на UIKit,
/// но служебные символы скрыты всегда (LiveMarkdown.hiddenRanges). Сам текст не
/// меняется: красятся атрибуты той же строки, она же хранится и синкается.
enum LiveMarkdownStyler {
    /// Строка-разделитель `---` — по ней рисуется линия.
    static let dividerKey = NSAttributedString.Key("thoughts.markdownDivider")
    /// `-` маркера списка, который рисуется как `•`.
    static let bulletKey = NSAttributedString.Key("thoughts.markdownBullet")
    /// Строки цитаты (значение — NSRange всей цитаты) — для поля и полосы.
    static let quoteKey = NSAttributedString.Key("thoughts.markdownQuote")
    /// Пробел после скрытого `- [ ]` (значение — отмечен ли пункт): на нём квадратик.
    static let taskBoxKey = NSAttributedString.Key("thoughts.markdownTaskBox")
    /// Строки блока кода (значение — NSRange всего блока) — для подложки.
    static let codeBlockKey = NSAttributedString.Key("thoughts.markdownCodeBlock")
    /// Адрес ссылки (URL) на её тексте — тап открывает (не .link: тот мешал бы правке).
    static let linkKey = NSAttributedString.Key("thoughts.markdownLink")

    static let font = UIFont.systemFont(ofSize: 17)
    static let color = UIColor(white: 1, alpha: 0.88)
    static let accent = UIColor(red: 0.42, green: 0.36, blue: 0.96, alpha: 1)
    static let codeColor = UIColor(white: 1, alpha: 0.7)
    /// Отступ под квадратик чек-листа.
    static let taskIndent: CGFloat = 26

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color, .paragraphStyle: blockStyle()]
    }

    /// Перекрашивает весь текст; возвращает разбор (для курсора и панели).
    /// shortcut: каждый раз целиком — для заметок это доли миллисекунды; на очень
    /// длинных текстах перекрашивать только изменённые абзацы.
    @discardableResult
    static func style(_ storage: NSTextStorage) -> [MarkdownStyler.Paragraph] {
        let full = NSRange(location: 0, length: storage.length)
        let paragraphs = MarkdownStyler.parse(storage.string)
        guard full.length > 0 else { return paragraphs }
        let filled = LiveMarkdown.filledCodeBlocks(paragraphs)
        var fenceLines: [NSRange] = []

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)

        for paragraph in paragraphs where paragraph.range.length > 0 {
            var paragraphFont = font
            switch paragraph.block {
            case .heading(let level):
                let scale: CGFloat = [1.5, 1.3, 1.15][level - 1]
                paragraphFont = withTraits(.traitBold, UIFont.systemFont(ofSize: font.pointSize * scale))
                storage.addAttribute(.font, value: paragraphFont, range: paragraph.range)
            case .divider:
                // Дефисы прозрачные (строке нужна своя высота), линию рисует LiveLayoutManager.
                storage.addAttribute(dividerKey, value: true, range: paragraph.range)
                storage.addAttribute(.foregroundColor, value: UIColor.clear, range: paragraph.range)
            case .bullet:
                if let marker = paragraph.blockMarker {
                    storage.addAttribute(bulletKey, value: true, range: NSRange(location: marker.location, length: 1))
                }
            case .quote:
                guard let block = paragraph.quoteBlock else { break }
                storage.addAttribute(quoteKey, value: NSValue(range: block), range: paragraph.range)
                storage.addAttribute(.paragraphStyle, value: blockStyle(
                    indent: 14, tail: -8,
                    before: paragraph.range.location == block.location ? 10 : 0,
                    after: NSMaxRange(paragraph.range) == NSMaxRange(block) ? 10 : 0
                ), range: paragraph.range)
            case .task(let done):
                guard let marker = paragraph.blockMarker else { break }
                storage.addAttribute(taskBoxKey, value: done, range: NSRange(location: NSMaxRange(marker) - 1, length: 1))
                storage.addAttribute(.paragraphStyle, value: blockStyle(indent: taskIndent), range: paragraph.range)
                let body = NSRange(location: NSMaxRange(marker), length: NSMaxRange(paragraph.range) - NSMaxRange(marker))
                if done, body.length > 0 {
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: body)
                    storage.addAttribute(.foregroundColor, value: color.withAlphaComponent(0.45), range: body)
                }
            case .codeFence:
                guard let block = paragraph.codeBlock, filled.contains(block.location) else { break }
                // ``` не видны и почти не занимают места — узкое поле блока.
                storage.addAttribute(codeBlockKey, value: NSValue(range: block), range: paragraph.range)
                storage.addAttributes([.font: UIFont.systemFont(ofSize: 4), .foregroundColor: UIColor.clear], range: paragraph.range)
                fenceLines.append(paragraph.range)
            case .code:
                storage.addAttributes([.font: mono(font.pointSize), .foregroundColor: codeColor,
                                       .paragraphStyle: blockStyle(indent: 10, tail: -10)], range: paragraph.range)
                if let block = paragraph.codeBlock {
                    storage.addAttribute(codeBlockKey, value: NSValue(range: block), range: paragraph.range)
                }
            case .paragraph, .numbered:
                break
            }

            for (range, style) in paragraph.inlines {
                switch style {
                case .bold: addTrait(.traitBold, to: storage, in: range)
                case .italic: addTrait(.traitItalic, to: storage, in: range)
                case .strikethrough:
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                case .underline:
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                case .highlight:
                    storage.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.35), range: range)
                case .code:
                    storage.addAttributes([.font: mono(paragraphFont.pointSize), .foregroundColor: codeColor,
                                           .backgroundColor: UIColor(white: 1, alpha: 0.08)], range: range)
                case .link(let url):
                    // Не .link: в редактируемом UITextView ссылка перехватывала бы касания.
                    storage.addAttributes([.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue], range: range)
                    if let target = URL(string: url) { storage.addAttribute(linkKey, value: target, range: range) }
                }
            }
        }

        // Скрытое — прозрачное и почти нулевой ширины, но остаётся в своей строке
        // (как на Mac: глифы нулевой ширины уезжали в строку выше).
        for range in LiveMarkdown.hiddenRanges(paragraphs) where !fenceLines.contains(range) {
            hide(range, in: storage)
        }
        storage.endEditing()
        return paragraphs
    }

    static func hide(_ range: NSRange, in storage: NSTextStorage) {
        storage.addAttributes([.font: hiddenFont, .foregroundColor: UIColor.clear], range: range)
    }

    private static let hiddenFont = UIFont.systemFont(ofSize: 0.1)

    private static func mono(_ size: CGFloat) -> UIFont {
        .monospacedSystemFont(ofSize: size * 0.9, weight: .regular)
    }

    private static func withTraits(_ trait: UIFontDescriptor.SymbolicTraits, _ font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait)) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    private static func addTrait(_ trait: UIFontDescriptor.SymbolicTraits, to storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? UIFont else { return }
            storage.addAttribute(.font, value: withTraits(trait, font), range: subrange)
        }
    }

    static func blockStyle(indent: CGFloat = 0, tail: CGFloat = 0, before: CGFloat = 0, after: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        style.tailIndent = tail
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        return style
    }
}
