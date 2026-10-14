import AppKit

/// Раскраска Markdown карточки поверх той же строки: шрифт, начертание,
/// зачёркивание, подчёркивание, выделение, ссылки — по разбору
/// MarkdownStyler. Сам текст не меняется, поэтому раскраска не попадает в
/// undo и не вызывает textDidChange.
enum MarkdownRenderer {
    /// Отметка строки-разделителя `---` — по ней CardNSTextView рисует линию.
    static let dividerKey = NSAttributedString.Key("thoughts.markdownDivider")
    /// Служебные символы, которые сейчас не показываются (глиф нулевой
    /// ширины, см. MarkdownGlyphHider).
    static let hiddenKey = NSAttributedString.Key("thoughts.markdownHidden")
    /// `-` маркера списка, который рисуется как `•`.
    static let bulletKey = NSAttributedString.Key("thoughts.markdownBullet")

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
        for paragraph in MarkdownStyler.parse(storage.string) where paragraph.range.length > 0 {
            var paragraphFont = typography.font
            switch paragraph.block {
            case .heading(let level):
                let scale: CGFloat = [1.5, 1.3, 1.15][level - 1]
                paragraphFont = NSFontManager.shared.convert(
                    NSFont(descriptor: typography.font.fontDescriptor, size: typography.font.pointSize * scale) ?? typography.font,
                    toHaveTrait: .boldFontMask
                )
                storage.addAttribute(.font, value: paragraphFont, range: paragraph.range)
                // `# ` виден, пока курсор на строке заголовка, — как остальные символы.
                if let marker = paragraph.blockMarker, !touches(selection, paragraph.range) {
                    storage.addAttribute(hiddenKey, value: true, range: marker)
                }
            case .divider:
                storage.addAttribute(dividerKey, value: true, range: paragraph.range)
                // Пока курсор на строке, `---` видно и его можно править. Иначе
                // — прозрачные дефисы, а не скрытые глифы: строке нужна своя
                // высота, линию CardNSTextView рисует по её середине (глифы
                // нулевой ширины AppKit относит к предыдущей строке).
                if !touches(selection, paragraph.range) {
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: paragraph.range)
                }
            case .bullet:
                if let marker = paragraph.blockMarker {
                    storage.addAttribute(bulletKey, value: true, range: NSRange(location: marker.location, length: 1))
                }
            default:
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
                case .link(let url):
                    if let target = URL(string: url) {
                        storage.addAttribute(.link, value: target, range: range)
                        linkedRanges.append(range)
                    }
                }
            }

            // `#` и `---` бледные; `•` списка — цветом текста.
            if let marker = paragraph.blockMarker, paragraph.block != .bullet,
               paragraph.block != .divider || touches(selection, paragraph.range) {
                storage.addAttribute(.foregroundColor, value: markerColor, range: marker)
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
                      !linkedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                      ns.substring(with: match.range).contains(".") else { continue }
                storage.addAttribute(.link, value: url, range: match.range)
            }
        }
        storage.endEditing()
    }

    /// Курсор внутри диапазона или вплотную к нему (как в Bear: только что
    /// напечатанное `**жирное**` ещё показывает звёздочки).
    private static func touches(_ selection: NSRange?, _ range: NSRange) -> Bool {
        guard let selection else { return false }
        if selection.length > 0 { return NSIntersectionRange(selection, range).length > 0 }
        return selection.location >= range.location && selection.location <= NSMaxRange(range)
    }

    private static func addTrait(_ trait: NSFontTraitMask, to storage: NSMutableAttributedString, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }
}
