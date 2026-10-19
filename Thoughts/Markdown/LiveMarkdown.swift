import Foundation

/// Живой Markdown редактора iPhone: служебные символы скрыты всегда (на Mac —
/// видны у курсора). Чистые правила поверх MarkdownStyler.parse: что скрыто,
/// где курсору нельзя стоять, что стирает Backspace, чем продолжается список.
/// Текст по-прежнему обычный Markdown — хранение и синк не меняются.
nonisolated enum LiveMarkdown {
    /// Позиции курсора `lower...upper` недопустимы — курсор переносится в `target`.
    struct Atom: Equatable {
        var lower: Int
        var upper: Int
        var target: Int
    }

    /// Блоки кода, в которых уже есть строка кода: пустой или одиночный ``` —
    /// ещё не блок, а просто текст (как на Mac).
    static func filledCodeBlocks(_ paragraphs: [MarkdownStyler.Paragraph]) -> Set<Int> {
        Set(paragraphs.filter { $0.block == .code }.compactMap { $0.codeBlock?.location })
    }

    /// Скрытые символы: `# `, `> `, `- [ ]` (пробел остаётся — на нём рисуется
    /// квадратик), `**`, `[`, `](url)`, `\` и строки ``` заполненных блоков кода.
    static func hiddenRanges(_ paragraphs: [MarkdownStyler.Paragraph]) -> [NSRange] {
        let filled = filledCodeBlocks(paragraphs)
        var result: [NSRange] = []
        for paragraph in paragraphs {
            switch paragraph.block {
            case .heading, .quote:
                if let marker = paragraph.blockMarker { result.append(marker) }
            case .task:
                if let marker = paragraph.blockMarker, marker.length > 1 {
                    result.append(NSRange(location: marker.location, length: marker.length - 1))
                }
            case .codeFence:
                if let block = paragraph.codeBlock, filled.contains(block.location) { result.append(paragraph.range) }
            default:
                break
            }
            result += paragraph.markers
        }
        return result.filter { $0.length > 0 }
    }

    /// Куда курсору нельзя: внутрь и в начало маркера блока (печать там сломала
    /// бы заголовок или пункт), внутрь `**` (открывающие — за них, к тексту;
    /// закрывающие — перед ними, тоже к тексту), на строки ``` блока кода.
    static func atoms(_ paragraphs: [MarkdownStyler.Paragraph], length: Int) -> [Atom] {
        let filled = filledCodeBlocks(paragraphs)
        var result: [Atom] = []
        for paragraph in paragraphs {
            switch paragraph.block {
            case .heading, .quote, .task, .bullet:
                if let marker = paragraph.blockMarker, marker.length > 0 {
                    result.append(Atom(lower: marker.location, upper: NSMaxRange(marker) - 1, target: NSMaxRange(marker)))
                }
            case .codeFence:
                guard let block = paragraph.codeBlock, filled.contains(block.location) else { break }
                let line = paragraph.range
                let isOpening = line.location == block.location
                let target = isOpening ? min(NSMaxRange(line) + 1, length) : max(line.location - 1, 0)
                result.append(Atom(lower: line.location, upper: NSMaxRange(line), target: target))
            default:
                break
            }
            for marker in paragraph.markers where marker.length > 1 {
                let isOpening = paragraph.spans.contains { $0.location == marker.location }
                result.append(Atom(lower: marker.location + 1, upper: NSMaxRange(marker) - 1,
                                   target: isOpening ? NSMaxRange(marker) : marker.location))
            }
        }
        return result
    }

    /// Позиция курсора после переноса из недопустимого места.
    static func snap(_ location: Int, atoms: [Atom]) -> Int {
        var location = location
        // Цель одного атома может оказаться в другом (`# **` подряд) — несколько шагов.
        for _ in 0..<4 {
            guard let atom = atoms.first(where: { $0.lower <= location && location <= $0.upper }) else { break }
            location = atom.target
        }
        return location
    }

    /// Что стирает Backspace при курсоре `location`; nil — обычное поведение.
    /// - сразу за маркером блока — снять оформление строки (весь маркер);
    /// - перед курсором скрытые символы — стереть видимый символ перед ними;
    /// - если это последняя буква фрагмента (`**a**`) — стереть фрагмент целиком,
    ///   иначе останутся голые `****`.
    /// `paragraphs` — готовый разбор `text`, если он уже есть (редактор не разбирает заново).
    static func backspaceRange(at location: Int, text: String, paragraphs: [MarkdownStyler.Paragraph]? = nil) -> NSRange? {
        guard location > 0 else { return nil }
        let paragraphs = paragraphs ?? MarkdownStyler.parse(text)
        for (index, paragraph) in paragraphs.enumerated() {
            guard let marker = paragraph.blockMarker, NSMaxRange(marker) == location else { continue }
            // Пустая строка цитаты под другой строкой цитаты — убрать её целиком, курсор —
            // в конец строки выше (как в Заметках). Одиночная цитата — просто снять `> `.
            if paragraph.block == .quote, NSMaxRange(paragraph.range) == location,
               index > 0, paragraphs[index - 1].block == .quote {
                return NSRange(location: paragraph.range.location - 1, length: marker.length + 1)
            }
            switch paragraph.block {
            case .heading, .quote, .task, .bullet: return marker
            default: break
            }
        }
        let hidden = hiddenRanges(paragraphs)
        func isHidden(_ index: Int) -> Bool { hidden.contains { NSLocationInRange(index, $0) } }
        var target = location - 1
        while target >= 0, isHidden(target) { target -= 1 }
        guard target >= 0 else { return nil }
        for paragraph in paragraphs {
            for span in paragraph.spans where NSLocationInRange(target, span) {
                let visible = (span.location..<NSMaxRange(span)).filter { !isHidden($0) }
                if visible.count == 1 { return span }
            }
        }
        return target == location - 1 ? nil : NSRange(location: target, length: 1)
    }

    /// Return на пустой строке блока кода после строки кода (второй Return подряд) —
    /// выйти из блока: пустая строка убирается, курсор — на строку после ```
    /// (у незакрытого блока ``` дописывается). Как у списков и цитат.
    private static func codeBlockExit(at location: Int, text: String, paragraphs: [MarkdownStyler.Paragraph]) -> MarkdownFormatting.Edit? {
        let ns = text as NSString
        // Пустая последняя строка незакрытого блока разбор отдаёт абзацем, а не кодом.
        guard let index = paragraphs.firstIndex(where: { $0.range.length == 0 && $0.range.location == location }),
              index > 0, paragraphs[index - 1].block == .code,
              paragraphs[index].block == .code || index == paragraphs.count - 1 else { return nil }
        let emptyLine = paragraphs[index].range
        let newlineBefore = NSRange(location: emptyLine.location - 1, length: 1)
        guard index + 1 < paragraphs.count, paragraphs[index + 1].block == .codeFence else {
            // Незакрытый блок: пустая строка становится закрывающей ```.
            return .init(range: emptyLine, replacement: "```\n", selection: NSRange(location: emptyLine.location + 4, length: 0))
        }
        let fence = paragraphs[index + 1].range
        if NSMaxRange(fence) < ns.length {
            // За ``` есть текст: убрать пустую строку, курсор — в начало строки после ```.
            return .init(range: newlineBefore, replacement: "", selection: NSRange(location: NSMaxRange(fence), length: 0))
        }
        // ``` в конце текста — новая строка после него.
        return .init(range: NSRange(location: newlineBefore.location, length: NSMaxRange(fence) - newlineBefore.location),
                     replacement: "\n```\n", selection: NSRange(location: newlineBefore.location + 5, length: 0))
    }

    /// Return в пункте списка: продолжить список (`- `, `- [ ] `, `> `, `2. `);
    /// в пустом пункте — снять маркер. nil — обычный перевод строки.
    static func newline(at location: Int, text: String, paragraphs: [MarkdownStyler.Paragraph]? = nil) -> MarkdownFormatting.Edit? {
        let ns = text as NSString
        if let exit = codeBlockExit(at: location, text: text, paragraphs: paragraphs ?? MarkdownStyler.parse(text)) { return exit }
        let line = MarkdownStyler.paragraph(in: ns, lineRange: ns.lineRange(for: NSRange(location: location, length: 0)))
        guard location == NSMaxRange(line.range) else { return nil }
        let content = ns.substring(with: line.range)
        let next: String
        switch line.block {
        case .bullet: next = "- "
        case .task: next = "- [ ] "
        case .quote: next = "> "
        case .numbered:
            let number = Int(content.prefix { $0.isNumber }) ?? 0
            next = "\(number + 1). "
        default: return nil
        }
        let markerLength = line.blockMarker?.length
            ?? ((content.range(of: #"^\d+\. "#, options: .regularExpression)).map { content.distance(from: $0.lowerBound, to: $0.upperBound) } ?? 0)
        if (content as NSString).length <= markerLength {
            // Пустой пункт — Return снимает маркер.
            return MarkdownFormatting.Edit(range: line.range, replacement: "", selection: NSRange(location: line.range.location, length: 0))
        }
        let insert = "\n" + next
        return MarkdownFormatting.Edit(range: NSRange(location: location, length: 0), replacement: insert,
                                       selection: NSRange(location: location + (insert as NSString).length, length: 0))
    }
}
