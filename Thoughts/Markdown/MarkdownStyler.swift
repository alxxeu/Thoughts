import Foundation

/// Разбор Markdown карточки для отображения: что как выглядит и где служебные
/// символы. Текст не меняет — редактор раскрашивает и прячет символы поверх
/// той же строки, она же хранится и синхронизируется. Все диапазоны — NSRange
/// в UTF-16 исходной строки, как у NSTextStorage.
///
/// Набор синтаксиса — как в Bear 2: `# ## ###`, `**жирный**`, `*курсив*`,
/// `~~зачёркнутый~~`, `~подчёркнутый~`, `==выделение==`, `` `код` ``,
/// `[текст](url)`, `- ` и `1. ` списки, `- [ ] ` чек-листы, `> ` цитаты,
/// блоки кода ```` ``` ````, `--`…`----------` разделитель, `\*` экранирование.
/// shortcut: свой упрощённый разбор, не полный CommonMark (нет `_`, таблиц,
/// вложенных списков) — расширять вместе с редактором.
enum MarkdownStyler {
    enum Block: Equatable {
        case paragraph
        case heading(Int)
        case bullet
        case numbered
        case divider
        case quote
        case task(done: Bool)
        /// Строка ```` ``` ```` — начало или конец блока кода.
        case codeFence
        /// Строка внутри блока кода — без разметки.
        case code
    }

    enum Inline: Equatable {
        case bold, italic, strikethrough, underline, highlight, code
        case link(String)
    }

    struct Paragraph: Equatable {
        /// Строка без завершающего перевода строки.
        var range: NSRange
        var block: Block
        /// Префикс блока, который заменяется отрисовкой: `# `, `- `, вся строка `---`.
        var blockMarker: NSRange?
        var inlines: [(range: NSRange, style: Inline)]
        /// Служебные символы внутри строки: `**`, `[`, `](url)`, `\` и т.п.
        var markers: [NSRange]
        /// Фрагменты целиком, вместе со своими служебными символами (`**a**`,
        /// `[a](url)`, `\*`) — символы фрагмента показываются, только пока
        /// курсор рядом с ним.
        var spans: [NSRange] = []
        /// У строк блока кода (и его ```) — весь блок, от ``` до ```.
        var codeBlock: NSRange?

        static func == (lhs: Paragraph, rhs: Paragraph) -> Bool {
            lhs.range == rhs.range && lhs.block == rhs.block && lhs.blockMarker == rhs.blockMarker
                && lhs.markers == rhs.markers && lhs.spans == rhs.spans && lhs.codeBlock == rhs.codeBlock
                && lhs.inlines.map(\.range) == rhs.inlines.map(\.range)
                && lhs.inlines.map(\.style) == rhs.inlines.map(\.style)
        }
    }

    static func parse(_ text: String) -> [Paragraph] {
        let ns = text as NSString
        var result: [Paragraph] = []
        var location = 0
        // Индекс строки с открывающим ``` — пока блок кода не закрыт.
        var openFence: Int?
        repeat {
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            let range = contentRange(in: ns, lineRange: lineRange)
            let isFence = ns.substring(with: range).trimmingCharacters(in: .whitespaces).hasPrefix("```")
            if isFence || openFence != nil {
                let block: Block = isFence ? .codeFence : .code
                result.append(Paragraph(range: range, block: block, blockMarker: isFence ? range : nil, inlines: [], markers: []))
                if isFence, let start = openFence {
                    closeCodeBlock(&result, from: start)
                    openFence = nil
                } else if isFence {
                    openFence = result.count - 1
                }
            } else {
                result.append(paragraph(in: ns, lineRange: lineRange))
            }
            location = NSMaxRange(lineRange)
        } while location < ns.length
        // Незакрытый блок кода тянется до конца текста.
        if let start = openFence { closeCodeBlock(&result, from: start) }
        if ns.length > 0, text.hasSuffix("\n") {
            result.append(Paragraph(range: NSRange(location: ns.length, length: 0), block: .paragraph, blockMarker: nil, inlines: [], markers: []))
        }
        return result
    }

    private static func closeCodeBlock(_ result: inout [Paragraph], from start: Int) {
        let block = NSRange(location: result[start].range.location, length: NSMaxRange(result[result.count - 1].range) - result[start].range.location)
        for index in start..<result.count { result[index].codeBlock = block }
    }

    /// Строка без завершающего перевода строки.
    private static func contentRange(in ns: NSString, lineRange: NSRange) -> NSRange {
        var contentEnd = NSMaxRange(lineRange)
        while contentEnd > lineRange.location, isNewline(ns.character(at: contentEnd - 1)) {
            contentEnd -= 1
        }
        return NSRange(location: lineRange.location, length: contentEnd - lineRange.location)
    }

    /// Разбор одной строки вне блока кода; lineRange может включать перевод строки.
    static func paragraph(in ns: NSString, lineRange: NSRange) -> Paragraph {
        let range = contentRange(in: ns, lineRange: lineRange)
        let line = ns.substring(with: range)

        // Разделитель — строка из 2–10 дефисов (`--` — наше расширение,
        // в стандартном Markdown минимум три).
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if (2...10).contains(trimmed.count), trimmed.allSatisfy({ $0 == "-" }) {
            return Paragraph(range: range, block: .divider, blockMarker: range, inlines: [], markers: [])
        }

        var block = Block.paragraph
        var blockMarker: NSRange?
        var bodyStart = range.location
        if let match = line.range(of: #"^#{1,3} "#, options: .regularExpression) {
            let length = line.distance(from: match.lowerBound, to: match.upperBound)
            block = .heading(length - 1)
            blockMarker = NSRange(location: range.location, length: length)
            bodyStart += length
        } else if line.range(of: #"^- \[[ xX]\] "#, options: .regularExpression) != nil {
            let done = line.dropFirst(3).first != " "
            block = .task(done: done)
            blockMarker = NSRange(location: range.location, length: 6)
            bodyStart += 6
        } else if line.hasPrefix("> ") || line == ">" {
            let length = min(2, (line as NSString).length)
            block = .quote
            blockMarker = NSRange(location: range.location, length: length)
            bodyStart += length
        } else if line.hasPrefix("- ") {
            block = .bullet
            blockMarker = NSRange(location: range.location, length: 2)
            bodyStart += 2
        } else if line.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
            // Номер — видимый текст, а не служебный символ: не прячем.
            block = .numbered
        }

        let body = NSRange(location: bodyStart, length: NSMaxRange(range) - bodyStart)
        var paragraph = Paragraph(range: range, block: block, blockMarker: blockMarker, inlines: [], markers: [])
        scanInlines(in: ns, range: body, into: &paragraph)
        return paragraph
    }

    /// Текст без разметки — для Spotlight и всего, что показывает текст «как читается».
    static func plainText(_ text: String) -> String {
        let ns = text as NSString
        return parse(text).map { paragraph -> String in
            switch paragraph.block {
            case .divider, .codeFence:
                return ""
            case .code:
                return ns.substring(with: paragraph.range)
            default:
                var hidden = paragraph.markers
                if let marker = paragraph.blockMarker { hidden.append(marker) }
                var line = ""
                var cursor = paragraph.range.location
                for marker in hidden.sorted(by: { $0.location < $1.location }) where marker.location >= cursor {
                    line += ns.substring(with: NSRange(location: cursor, length: marker.location - cursor))
                    cursor = NSMaxRange(marker)
                }
                line += ns.substring(with: NSRange(location: cursor, length: NSMaxRange(paragraph.range) - cursor))
                switch paragraph.block {
                case .bullet: return "\u{2022} " + line
                case .task(let done): return (done ? "\u{2611} " : "\u{2610} ") + line
                default: return line
                }
            }
        }.joined(separator: "\n")
    }

    /// Символы, которые в обычном тексте нужно экранировать, чтобы они не стали разметкой.
    static let specialCharacters: Set<Character> = ["\\", "*", "~", "=", "`", "[", "]", "#"]

    // MARK: - Inline

    private struct Opener {
        var char: unichar
        var length: Int
        var location: Int
    }

    private static func scanInlines(in ns: NSString, range: NSRange, into paragraph: inout Paragraph) {
        var openers: [Opener] = []
        var i = range.location
        let end = NSMaxRange(range)

        while i < end {
            let c = ns.character(at: i)

            // \* — символ как есть, обратный слэш служебный.
            if c == backslash, i + 1 < end, isEscapable(ns.character(at: i + 1)) {
                paragraph.markers.append(NSRange(location: i, length: 1))
                paragraph.spans.append(NSRange(location: i, length: 2))
                i += 2
                continue
            }

            // `код` — внутри никакой другой разметки.
            if c == backtick {
                if let close = find(backtick, in: ns, from: i + 1, to: end), close > i + 1 {
                    paragraph.markers.append(NSRange(location: i, length: 1))
                    paragraph.markers.append(NSRange(location: close, length: 1))
                    paragraph.inlines.append((NSRange(location: i + 1, length: close - i - 1), .code))
                    paragraph.spans.append(NSRange(location: i, length: close - i + 1))
                    i = close + 1
                    continue
                }
                i += 1
                continue
            }

            // [текст](url)
            if c == openBracket, let link = linkMatch(in: ns, at: i, end: end) {
                paragraph.markers.append(NSRange(location: i, length: 1))
                paragraph.markers.append(link.tail)
                paragraph.inlines.append((link.text, .link(link.url)))
                // Текст ссылки тоже может быть жирным и т.п. — разбираем отдельно.
                var inner = Paragraph(range: link.text, block: .paragraph, blockMarker: nil, inlines: [], markers: [])
                scanInlines(in: ns, range: link.text, into: &inner)
                paragraph.inlines += inner.inlines
                paragraph.markers += inner.markers
                paragraph.spans += inner.spans
                paragraph.spans.append(NSRange(location: i, length: NSMaxRange(link.tail) - i))
                i = NSMaxRange(link.tail)
                continue
            }

            guard c == asterisk || c == tilde || c == equals else {
                i += 1
                continue
            }

            var runEnd = i
            while runEnd < end, ns.character(at: runEnd) == c { runEnd += 1 }
            var remaining = runEnd - i
            var position = i
            let before: unichar? = i > range.location ? ns.character(at: i - 1) : nil
            let after: unichar? = runEnd < end ? ns.character(at: runEnd) : nil

            // Закрытие: сначала то, что открыто последним (*** закрывает * и **).
            if let before, !isWhitespace(before) {
                while remaining > 0, let top = openers.last, top.char == c, top.length <= remaining {
                    openers.removeLast()
                    let contentStart = top.location + top.length
                    if position > contentStart, let style = style(for: c, length: top.length) {
                        paragraph.markers.append(NSRange(location: top.location, length: top.length))
                        paragraph.markers.append(NSRange(location: position, length: top.length))
                        paragraph.inlines.append((NSRange(location: contentStart, length: position - contentStart), style))
                        paragraph.spans.append(NSRange(location: top.location, length: position + top.length - top.location))
                    }
                    position += top.length
                    remaining -= top.length
                }
            }

            // Открытие: длинный разделитель снаружи, короткий внутри (*** = ** + *).
            if remaining > 0, let after, !isWhitespace(after) {
                for length in [2, 1] where remaining >= length && style(for: c, length: length) != nil {
                    openers.append(Opener(char: c, length: length, location: position))
                    position += length
                    remaining -= length
                }
            }
            i = runEnd
        }
    }

    private static func style(for char: unichar, length: Int) -> Inline? {
        switch (char, length) {
        case (asterisk, 2): return .bold
        case (asterisk, 1): return .italic
        case (tilde, 2): return .strikethrough
        case (tilde, 1): return .underline
        case (equals, 2): return .highlight
        default: return nil
        }
    }

    private static func linkMatch(in ns: NSString, at start: Int, end: Int) -> (text: NSRange, tail: NSRange, url: String)? {
        guard let closeBracket = find(closeBracketChar, in: ns, from: start + 1, to: end),
              closeBracket > start + 1,
              closeBracket + 1 < end, ns.character(at: closeBracket + 1) == openParen,
              let closeParen = find(closeParenChar, in: ns, from: closeBracket + 2, to: end),
              closeParen > closeBracket + 2 else { return nil }
        let url = ns.substring(with: NSRange(location: closeBracket + 2, length: closeParen - closeBracket - 2))
        guard !url.contains(" ") else { return nil }
        return (
            NSRange(location: start + 1, length: closeBracket - start - 1),
            NSRange(location: closeBracket, length: closeParen - closeBracket + 1),
            url
        )
    }

    private static func find(_ char: unichar, in ns: NSString, from: Int, to end: Int) -> Int? {
        var i = from
        while i < end {
            if ns.character(at: i) == char { return i }
            i += 1
        }
        return nil
    }

    private static let backslash = unichar(UInt8(ascii: "\\"))
    private static let backtick = unichar(UInt8(ascii: "`"))
    private static let asterisk = unichar(UInt8(ascii: "*"))
    private static let tilde = unichar(UInt8(ascii: "~"))
    private static let equals = unichar(UInt8(ascii: "="))
    private static let openBracket = unichar(UInt8(ascii: "["))
    private static let closeBracketChar = unichar(UInt8(ascii: "]"))
    private static let openParen = unichar(UInt8(ascii: "("))
    private static let closeParenChar = unichar(UInt8(ascii: ")"))

    private static func isEscapable(_ c: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(c) else { return false }
        return specialCharacters.contains(Character(scalar))
    }

    private static func isWhitespace(_ c: unichar) -> Bool {
        c == 0x20 || c == 0x09 || isNewline(c)
    }

    private static func isNewline(_ c: unichar) -> Bool {
        c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029
    }
}
