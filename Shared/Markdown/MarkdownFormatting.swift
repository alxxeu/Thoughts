import Foundation

/// Команды Format (⌘B, ⌘I, …): обернуть выделение в символы Markdown или,
/// если оно уже обёрнуто, снять их. Чистая функция — правку применяет
/// редактор через shouldChangeText/didChangeText, чтобы работал ⌘Z.
enum MarkdownFormatting {
    struct Edit: Equatable {
        var range: NSRange
        var replacement: String
        var selection: NSRange
    }

    static func toggle(_ marker: String, in text: NSString, selection: NSRange) -> Edit {
        let m = (marker as NSString).length

        // Уже обёрнуто снаружи: **|выделение|**
        if selection.location >= m, NSMaxRange(selection) + m <= text.length,
           isExactMarker(marker, in: text, at: selection.location - m),
           isExactMarker(marker, in: text, at: NSMaxRange(selection)) {
            return Edit(
                range: NSRange(location: selection.location - m, length: selection.length + 2 * m),
                replacement: text.substring(with: selection),
                selection: NSRange(location: selection.location - m, length: selection.length)
            )
        }

        // Выделены и сами символы: |**текст**|
        let selected = text.substring(with: selection)
        if selection.length > 2 * m,
           isExactMarker(marker, in: text, at: selection.location),
           isExactMarker(marker, in: text, at: NSMaxRange(selection) - m) {
            let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
            return Edit(range: selection, replacement: inner, selection: NSRange(location: selection.location, length: (inner as NSString).length))
        }

        // Пустое выделение — пара символов, курсор между ними.
        guard selection.length > 0 else {
            return Edit(range: selection, replacement: marker + marker, selection: NSRange(location: selection.location + m, length: 0))
        }

        // Обернуть: каждую строку отдельно (разметка не переходит через
        // перевод строки), пробелы по краям — снаружи символов.
        let wrapped = selected.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return line }
            let leading = line.prefix { $0 == " " || $0 == "\t" }
            let trailing = String(line.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
            return leading + marker + trimmed + marker + trailing
        }.joined(separator: "\n")
        let isSingleLine = !selected.contains("\n") && selected.trimmingCharacters(in: .whitespaces) == selected
        return Edit(
            range: selection,
            replacement: wrapped,
            selection: isSingleLine
                ? NSRange(location: selection.location + m, length: selection.length)
                : NSRange(location: selection.location, length: (wrapped as NSString).length)
        )
    }

    /// Блок кода: обернуть строки выделения в ```` ``` ```` (каждая ограда — своей
    /// строкой); если они уже стоят строками выше и ниже — снять.
    static func toggleCodeBlock(in text: NSString, selection: NSRange) -> Edit {
        let lines = text.lineRange(for: selection)
        var body = lines
        if body.length > 0, text.character(at: NSMaxRange(body) - 1) == 0x0A { body.length -= 1 }
        let offset = selection.location - body.location

        func isFence(_ line: NSRange) -> Bool {
            text.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```")
        }
        if body.location > 0, NSMaxRange(lines) < text.length {
            let above = text.lineRange(for: NSRange(location: body.location - 1, length: 0))
            let below = text.lineRange(for: NSRange(location: NSMaxRange(lines), length: 0))
            if isFence(above), isFence(below) {
                var end = NSMaxRange(below)
                if end > below.location, text.character(at: end - 1) == 0x0A { end -= 1 }
                return Edit(range: NSRange(location: above.location, length: end - above.location),
                            replacement: text.substring(with: body),
                            selection: NSRange(location: above.location + offset, length: selection.length))
            }
        }
        let opening = "```\n"
        return Edit(range: body, replacement: opening + text.substring(with: body) + "\n```",
                    selection: NSRange(location: selection.location + (opening as NSString).length, length: selection.length))
    }

    /// Ровно этот маркер, а не часть более длинного: `*` курсива не должен
    /// совпасть со звёздочкой из `**` жирного. Допускается и `***` (жирный
    /// курсив) — курсив снимается из него, жирный остаётся.
    private static func isExactMarker(_ marker: String, in text: NSString, at location: Int) -> Bool {
        let m = (marker as NSString).length
        guard text.substring(with: NSRange(location: location, length: m)) == marker else { return false }
        let char = (marker as NSString).character(at: 0)
        // Длина всей серии одинаковых символов вокруг маркера.
        var start = location
        while start > 0, text.character(at: start - 1) == char { start -= 1 }
        var end = location + m
        while end < text.length, text.character(at: end) == char { end += 1 }
        let run = end - start
        return run == m || run == 3
    }

    /// `[]`, `[ ]`, `- []`, `[x]` → стандартные `- [ ] ` / `- [x] `: так их
    /// понимают Notion и другие Markdown-приложения.
    ///
    /// Набор: пробел после `linePrefix` (всё от начала строки до курсора).
    /// Если вместе с пробелом это нестандартный маркер — какой стандартный
    /// вставить вместо префикса и пробела; иначе nil.
    static func standardTaskMarker(typingSpaceAfter linePrefix: String) -> String? {
        let candidate = linePrefix + " "
        guard let match = candidate.range(of: MarkdownStyler.taskPattern, options: .regularExpression),
              match.upperBound == candidate.endIndex else { return nil }
        let standard = candidate.lowercased().contains("x") ? "- [x] " : "- [ ] "
        return candidate == standard ? nil : standard
    }

    /// Вставка: нестандартные маркеры в начале строк вставляемого текста.
    /// `atLineStart` — вставка в начало строки; иначе первая строка
    /// продолжает чужую и её начало не трогается.
    static func standardizingTaskMarkers(_ text: String, atLineStart: Bool) -> String {
        var lines = text.components(separatedBy: "\n")
        for index in lines.indices where index > 0 || atLineStart {
            let line = lines[index]
            guard let match = line.range(of: MarkdownStyler.taskPattern, options: .regularExpression) else { continue }
            let standard = line[match].lowercased().contains("x") ? "- [x] " : "- [ ] "
            lines[index] = standard + line[match.upperBound...]
        }
        return lines.joined(separator: "\n")
    }
}
