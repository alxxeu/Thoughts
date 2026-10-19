import AppKit

/// Раскраска Markdown карточки поверх той же строки: шрифт, начертание,
/// зачёркивание, подчёркивание, выделение, ссылки — по разбору
/// MarkdownStyler. Сам текст не меняется, поэтому раскраска не попадает в
/// undo и не вызывает textDidChange.
enum MarkdownRenderer {
    /// Отметка строки-разделителя `---` — по ней CardNSTextView рисует линию.
    static let dividerKey = NSAttributedString.Key("thoughts.markdownDivider")
    /// Служебные символы Markdown (скрыты всегда): прозрачные и нулевой ширины
    /// (кернинг). Не глифы нулевой ширины (.null) — такие AppKit прикрепляет к
    /// концу предыдущей строки, и `> `/`# ` в начале строки уезжали в строку
    /// выше вместе со своим абзацем.
    static let hiddenKey = NSAttributedString.Key("thoughts.markdownHidden")
    /// `-` маркера списка, который рисуется как `•`.
    static let bulletKey = NSAttributedString.Key("thoughts.markdownBullet")
    /// Строки цитаты (значение — NSRange всей цитаты) — для поля и полосы.
    static let quoteKey = NSAttributedString.Key("thoughts.markdownQuote")
    /// Пробел после `[]` чек-листа (значение — отмечен ли пункт): по его строке
    /// CardNSTextView рисует квадратик слева, клик по нему отмечает пункт.
    static let taskBoxKey = NSAttributedString.Key("thoughts.markdownTaskBox")
    /// Строки блока кода (значение — NSRange всего блока) — для подложки.
    static let codeBlockKey = NSAttributedString.Key("thoughts.markdownCodeBlock")

    static func baseAttributes(_ typography: CardTypography) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        return [
            .font: typography.font,
            .foregroundColor: typography.color,
            .paragraphStyle: paragraph
        ]
    }

    /// Перекрашивает весь текст. Служебные символы скрыты всегда — что именно,
    /// решает LiveMarkdown.hiddenRanges (та же модель, что в редакторе iPhone).
    /// shortcut: каждый раз целиком — для карточек размером с заметку это
    /// микросекунды; если на очень длинных текстах начнёт подтормаживать,
    /// перекрашивать только изменённые абзацы.
    static func style(_ storage: NSMutableAttributedString, typography: CardTypography) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let ns = storage.string as NSString

        storage.beginEditing()
        storage.setAttributes(baseAttributes(typography), range: full)

        var linkedRanges: [NSRange] = []
        var codeRanges: [NSRange] = []

        let paragraphs = MarkdownStyler.parse(storage.string)
        let filledCodeBlocks = LiveMarkdown.filledCodeBlocks(paragraphs)
        var fenceLines: [NSRange] = []

        for paragraph in paragraphs where paragraph.range.length > 0 {
            var paragraphFont = typography.font
            let mono = NSFont.monospacedSystemFont(ofSize: typography.font.pointSize * 0.92, weight: .regular)
            switch paragraph.block {
            case .heading(let level):
                let scale: CGFloat = [1.5, 1.3, 1.15][level - 1]
                paragraphFont = NSFontManager.shared.convert(
                    NSFont(descriptor: typography.font.fontDescriptor, size: typography.font.pointSize * scale) ?? typography.font,
                    toHaveTrait: .boldFontMask
                )
                storage.addAttribute(.font, value: paragraphFont, range: paragraph.range)
            case .divider:
                storage.addAttribute(dividerKey, value: true, range: paragraph.range)
                // Прозрачные дефисы, а не скрытые глифы: строке нужна своя
                // высота, линию CardNSTextView рисует по её середине (глифы
                // нулевой ширины AppKit относит к предыдущей строке).
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: paragraph.range)
            case .bullet:
                if let marker = paragraph.blockMarker {
                    storage.addAttribute(bulletKey, value: true, range: NSRange(location: marker.location, length: 1))
                }
            case .quote:
                guard let block = paragraph.quoteBlock else { break }
                storage.addAttribute(quoteKey, value: NSValue(range: block), range: paragraph.range)
                // Отступ под полосу слева и место под иконку « справа; поля
                // сверху и снизу — у первой и последней строки цитаты.
                storage.addAttribute(.paragraphStyle, value: blockStyle(
                    indent: 18, tail: -26,
                    before: paragraph.range.location == block.location ? 12 : 0,
                    after: NSMaxRange(paragraph.range) == NSMaxRange(block) ? 12 : 0
                ), range: paragraph.range)
            case .task(let done):
                // Квадратик рисуется слева, на отступе строки: `- [ ]` скрыт
                // (LiveMarkdown.hiddenRanges), кроме пробела — у строки всегда есть видимый глиф,
                // по нему CardNSTextView находит строку (даже пустого пункта).
                guard let marker = paragraph.blockMarker else { break }
                let space = NSRange(location: NSMaxRange(marker) - 1, length: 1)
                storage.addAttribute(taskBoxKey, value: done, range: space)
                storage.addAttribute(.paragraphStyle, value: blockStyle(indent: taskIndent(typography)), range: paragraph.range)
                let body = NSRange(location: NSMaxRange(marker), length: NSMaxRange(paragraph.range) - NSMaxRange(marker))
                if done, body.length > 0 {
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: body)
                    storage.addAttribute(.foregroundColor, value: typography.color.withAlphaComponent(0.45), range: body)
                }
            case .codeFence:
                guard let block = paragraph.codeBlock, filledCodeBlocks.contains(block.location) else { break }
                storage.addAttribute(codeBlockKey, value: NSValue(range: block), range: paragraph.range)
                codeRanges.append(block)
                // ``` не видны и почти не занимают места — узкое поле блока,
                // а не пустая строка (прозрачные, а не скрытые: см. divider).
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 4), range: paragraph.range)
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: paragraph.range)
                fenceLines.append(paragraph.range)
            case .code:
                storage.addAttribute(.font, value: mono, range: paragraph.range)
                storage.addAttribute(.foregroundColor, value: codeColor(typography), range: paragraph.range)
                // Справа — место под кнопку копирования.
                storage.addAttribute(.paragraphStyle, value: blockStyle(tail: -26), range: paragraph.range)
                if let block = paragraph.codeBlock {
                    storage.addAttribute(codeBlockKey, value: NSValue(range: block), range: paragraph.range)
                }
            case .paragraph, .numbered:
                break
            }

            for (range, style) in paragraph.inlines {
                switch style {
                case .bold:
                    addTrait(.boldFontMask, to: storage, in: range)
                case .italic:
                    addTrait(.italicFontMask, to: storage, in: range)
                case .strikethrough:
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                case .underline:
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                case .highlight:
                    storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: range)
                case .code:
                    let mono = NSFont.monospacedSystemFont(ofSize: paragraphFont.pointSize * 0.92, weight: .regular)
                    storage.addAttribute(.font, value: mono, range: range)
                    storage.addAttribute(.foregroundColor, value: codeColor(typography), range: range)
                case .link(let url):
                    if let target = linkTarget(url) {
                        storage.addAttribute(.link, value: target, range: range)
                        linkedRanges.append(range)
                    }
                }
            }
        }

        for range in LiveMarkdown.hiddenRanges(paragraphs) where !fenceLines.contains(range) {
            storage.addAttribute(hiddenKey, value: true, range: range)
        }

        // Голые адреса — тоже ссылки. Автоопределение NSTextView выключено:
        // полная перекраска выше стирала бы его атрибуты.
        // Адрес внутри скрытого `](url)` ссылкой не делаем: NSTextView рисует .link
        // синим даже поверх прозрачного цвета — у скрытого текста выйдет «пятно».
        let hiddenLinkRanges = LiveMarkdown.hiddenRanges(paragraphs)
        if let detector = linkDetector {
            for match in detector.matches(in: storage.string, range: full) {
                guard let url = match.url,
                      !(linkedRanges + codeRanges + hiddenLinkRanges).contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                      ns.substring(with: match.range).contains(".") else { continue }
                storage.addAttribute(.link, value: url, range: match.range)
            }
        }
        // Скрытое — прозрачное и почти нулевой ширины, но остаётся в своей строке.
        storage.enumerateAttribute(hiddenKey, in: full) { value, range, _ in
            guard value != nil else { return }
            hide(range, in: storage)
        }
        storage.endEditing()
    }

    /// Прозрачно и без ширины (кернинг минус ширина символа), но шрифтом своей
    /// строки — как в редакторе iPhone. Крохотный шрифт сжимал строку, где кроме
    /// служебных символов пока ничего нет (`# `, `- [ ] `): после первой буквы
    /// курсор съезжал на строку ниже.
    private static func hide(_ range: NSRange, in storage: NSMutableAttributedString) {
        for index in range.location..<NSMaxRange(range) {
            let char = NSRange(location: index, length: 1)
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 15)
            // Глиф скрытого символа — пробел (MarkdownBulletGlyphs), его ширину и гасим.
            let width = " ".size(withAttributes: [.font: font]).width
            storage.addAttributes([.foregroundColor: NSColor.clear, .kern: -width], range: char)
        }
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Адрес ссылки с протоколом: `[текст](example.com)` без него система открыть
    /// не может (ошибка -50), поэтому дописываем https://.
    static func linkTarget(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hasScheme = trimmed.range(of: #"^(?:[A-Za-z][A-Za-z0-9+.-]*://|mailto:|tel:)"#, options: .regularExpression) != nil
        return URL(string: hasScheme ? trimmed : "https://" + trimmed)
    }

    /// Цвет кода — блоков и `инлайн`: нейтральный, светлее/бледнее текста.
    static func codeColor(_ typography: CardTypography) -> NSColor {
        typography.color.withAlphaComponent(0.7)
    }

    /// Ширина отступа под квадратик чек-листа.
    static func taskIndent(_ typography: CardTypography) -> CGFloat {
        (typography.font.pointSize * 1.5).rounded()
    }

    private static func blockStyle(indent: CGFloat = 0, tail: CGFloat = 0, before: CGFloat = 0, after: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        style.tailIndent = tail
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        return style
    }

    private static func addTrait(_ trait: NSFontTraitMask, to storage: NSMutableAttributedString, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }
}
