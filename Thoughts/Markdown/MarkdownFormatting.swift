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
    /// понимают Notion и другие Markdown-приложения. Правки идут с конца
    /// текста (более ранние диапазоны не сдвигаются); `cursor` — где окажется
    /// курсор после них: после маркера, если стоял в нём.
    static func normalizedTaskMarkers(in text: String, cursor: Int) -> (edits: [(range: NSRange, marker: String)], cursor: Int) {
        let ns = text as NSString
        var edits: [(range: NSRange, marker: String)] = []
        for paragraph in MarkdownStyler.parse(text) {
            guard case .task(let done) = paragraph.block, let marker = paragraph.blockMarker else { continue }
            let standard = done ? "- [x] " : "- [ ] "
            if ns.substring(with: marker) != standard { edits.append((marker, standard)) }
        }
        // С конца к началу: более поздние правки на позицию не влияют,
        // более ранние сдвигают её — диапазоны в исходных координатах.
        var newCursor = cursor
        for edit in edits.reversed() {
            let newLength = (edit.marker as NSString).length
            if NSMaxRange(edit.range) <= newCursor {
                newCursor += newLength - edit.range.length
            } else if edit.range.location < newCursor {
                newCursor = edit.range.location + newLength
            }
        }
        return (edits.reversed(), newCursor)
    }
}

