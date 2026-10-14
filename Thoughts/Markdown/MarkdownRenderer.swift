import AppKit

/// Раскраска Markdown карточки поверх той же строки: шрифт, начертание,
/// зачёркивание, подчёркивание, выделение, ссылки — по разбору
/// MarkdownStyler. Сам текст не меняется, поэтому раскраска не попадает в
/// undo и не вызывает textDidChange.
enum MarkdownRenderer {
    /// Отметка строки-разделителя `---` — по ней CardNSTextView рисует линию.
    static let dividerKey = NSAttributedString.Key("thoughts.markdownDivider")
    /// Служебные символы, которые сейчас не показываются: прозрачные и
    /// крохотного размера. Не глифы нулевой ширины (.null) — такие AppKit
    /// прикрепляет к концу предыдущей строки, и `> `/`# ` в начале строки
    /// уезжали в строку выше вместе со своим абзацем.
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

    /// Перекрашивает весь текст. `selection` — выделение в редакторе в фокусе:
    /// служебные символы фрагмента видны, только пока курсор его касается
    /// (как в Bear); nil — карточка не в фокусе, скрыто всё.
    /// shortcut: каждый раз целиком — для карточек размером с заметку это
    /// микросекунды; если на очень длинных текстах начнёт подтормаживать,
    /// перекрашивать только изменённые абзацы.
    static func style(_ storage: NSMutableAttributedString, typography: CardTypography, selection: NSRange? = nil) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let ns = storage.string as NSString
        let markerColor = typography.color.withAlphaComponent(0.35)

        storage.beginEditing()
        storage.setAttributes(baseAttributes(typography), range: full)

        var linkedRanges: [NSRange] = []
        var codeRanges: [NSRange] = []

        /// Бледный символ блока; скрыт, пока курсор не на его строке.
        func revealOrHide(_ marker: NSRange?, near range: NSRange) {
            guard let marker else { return }
            storage.addAttribute(.foregroundColor, value: markerColor, range: marker)
            if !touches(selection, range) {
                storage.addAttribute(hiddenKey, value: true, range: marker)
            }
        }
        /// Бледная строка, пока курсор рядом; иначе прозрачная (высота строки остаётся).
        func showOrClear(_ line: NSRange, near range: NSRange) {
            storage.addAttribute(.foregroundColor, value: touches(selection, range) ? markerColor : NSColor.clear, range: line)
        }

        let paragraphs = MarkdownStyler.parse(storage.string)
        // Блоки кода, в которых уже есть хоть одна строка кода: пустой или
        // одиночный ``` — ещё не блок, а просто текст.
        let filledCodeBlocks = Set(paragraphs.filter { $0.block == .code }.compactMap { $0.codeBlock?.location })

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
                // `# ` виден (бледно), пока курсор на строке заголовка, — как остальные символы.
                revealOrHide(paragraph.blockMarker, near: paragraph.range)
            case .divider:
                storage.addAttribute(dividerKey, value: true, range: paragraph.range)
                // Прозрачные дефисы, а не скрытые глифы: строке нужна своя
                // высота, линию CardNSTextView рисует по её середине (глифы
                // нулевой ширины AppKit относит к предыдущей строке).
                showOrClear(paragraph.range, near: paragraph.range)
            case .bullet:
                if let marker = paragraph.blockMarker {
                    storage.addAttribute(bulletKey, value: true, range: NSRange(location: marker.location, length: 1))
                }
            case .quote:
                guard let block = paragraph.quoteBlock else { break }
                storage.addAttribute(quoteKey, value: NSValue(range: block), range: paragraph.range)
                // Отступ под полосу слева и место под иконку « справа; поля
                // сверху и снизу — у первой и последней строки цитаты.
                // Пока `> ` видно, перенесённые строки выравниваются по
                // тексту после него, а не по самому `>`.
                let markerWidth = touches(selection, paragraph.range) && paragraph.blockMarker != nil
                    ? (ns.substring(with: paragraph.blockMarker!) as NSString).size(withAttributes: [.font: typography.font]).width
                    : 0
                storage.addAttribute(.paragraphStyle, value: blockStyle(
                    indent: 18, hanging: markerWidth, tail: -26,
                    before: paragraph.range.location == block.location ? 12 : 0,
                    after: NSMaxRange(paragraph.range) == NSMaxRange(block) ? 12 : 0
                ), range: paragraph.range)
                revealOrHide(paragraph.blockMarker, near: paragraph.range)
            case .task(let done):
                // Квадратик рисуется слева, на отступе строки: `[] ` скрыт
                // целиком, кроме пробела — у строки всегда есть видимый глиф,
                // по нему CardNSTextView находит строку (даже пустого пункта).
                guard let marker = paragraph.blockMarker else { break }
                let space = NSRange(location: NSMaxRange(marker) - 1, length: 1)
                storage.addAttribute(hiddenKey, value: true, range: NSRange(location: marker.location, length: marker.length - 1))
                storage.addAttribute(taskBoxKey, value: done, range: space)
                storage.addAttribute(.paragraphStyle, value: blockStyle(indent: taskIndent(typography)), range: paragraph.range)
                let body = NSRange(location: NSMaxRange(marker), length: NSMaxRange(paragraph.range) - NSMaxRange(marker))
                if done, body.length > 0 {
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: body)
                    storage.addAttribute(.foregroundColor, value: typography.color.withAlphaComponent(0.45), range: body)
                }
            case .codeFence:
                guard let block = paragraph.codeBlock, filledCodeBlocks.contains(block.location) else {
                    storage.addAttribute(.foregroundColor, value: markerColor, range: paragraph.range)
                    break
                }
                storage.addAttribute(codeBlockKey, value: NSValue(range: block), range: paragraph.range)
                codeRanges.append(block)
                if touches(selection, block) {
                    storage.addAttribute(.font, value: mono, range: paragraph.range)
                    storage.addAttribute(.foregroundColor, value: markerColor, range: paragraph.range)
                } else {
                    // ``` не видны и почти не занимают места — узкое поле блока,
                    // а не пустая строка (прозрачные, а не скрытые: см. divider).
                    storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 4), range: paragraph.range)
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: paragraph.range)
                }
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
                    if let target = URL(string: url) {
                        storage.addAttribute(.link, value: target, range: range)
                        linkedRanges.append(range)
                    }
                }
            }

            for marker in paragraph.markers {
                storage.addAttribute(.foregroundColor, value: markerColor, range: marker)
                let isRevealed = paragraph.spans.contains { NSLocationInRange(marker.location, $0) && touches(selection, $0) }
                if !isRevealed {
                    storage.addAttribute(hiddenKey, value: true, range: marker)
                }
            }
        }

        // Голые адреса — тоже ссылки. Автоопределение NSTextView выключено:
        // полная перекраска выше стирала бы его атрибуты.
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: storage.string, range: full) {
                guard let url = match.url,
                      !(linkedRanges + codeRanges).contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                      ns.substring(with: match.range).contains(".") else { continue }
                storage.addAttribute(.link, value: url, range: match.range)
            }
        }
        // Скрытое — прозрачное и почти нулевой ширины, но остаётся в своей строке.
        storage.enumerateAttribute(hiddenKey, in: full) { value, range, _ in
            guard value != nil else { return }
            storage.addAttributes([.font: hiddenFont, .foregroundColor: NSColor.clear], range: range)
        }
        storage.endEditing()
    }

    private static let hiddenFont = NSFont.systemFont(ofSize: 0.1)

    /// Курсор внутри диапазона или вплотную к нему (как в Bear: только что
    /// напечатанное `**жирное**` ещё показывает звёздочки).
    private static func touches(_ selection: NSRange?, _ range: NSRange) -> Bool {
        guard let selection else { return false }
        if selection.length > 0 { return NSIntersectionRange(selection, range).length > 0 }
        return selection.location >= range.location && selection.location <= NSMaxRange(range)
    }

    /// Цвет кода — блоков и `инлайн`: нейтральный, светлее/бледнее текста.
    static func codeColor(_ typography: CardTypography) -> NSColor {
        typography.color.withAlphaComponent(0.7)
    }

    /// Ширина отступа под квадратик чек-листа.
    static func taskIndent(_ typography: CardTypography) -> CGFloat {
        (typography.font.pointSize * 1.5).rounded()
    }

    private static func blockStyle(indent: CGFloat = 0, hanging: CGFloat = 0, tail: CGFloat = 0, before: CGFloat = 0, after: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.firstLineHeadIndent = indent
        style.headIndent = indent + hanging
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
