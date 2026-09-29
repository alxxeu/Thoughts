import AppKit

/// Читаемая копия заметок в одном Markdown-файле — для других приложений,
/// без обратного импорта (для этого есть .thoughtsbackup).
///
/// Space → `# Имя`, карточки внутри Space идут сверху вниз и слева
/// направо (как их читают на канве) и разделены `---`. Разделитель внутри
/// карточки — `* * *`, чтобы не путать с границей карточек. Bold/italic и
/// ссылки переносятся в синтаксис Markdown, маркеры "• " — в "- ".
enum MarkdownExporter {
    static func export(_ snapshot: BoardSnapshot, includeLocked: Bool, passcodeEnabled: Bool) -> String {
        var sections: [String] = []

        for workspace in snapshot.workspaces.sorted(by: { $0.slot < $1.slot }) {
            if workspace.isProtected && passcodeEnabled && !includeLocked { continue }

            let cards = snapshot.cards
                .filter { $0.workspaceSlot == workspace.slot }
                .filter { includeLocked || $0.privacyMode != CardPrivacyMode.lock.rawValue }
                .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            guard !cards.isEmpty else { continue }

            let body = cards.map { markdown(for: $0) }.joined(separator: "\n\n---\n\n")
            sections.append("# \(workspace.name)\n\n\(body)")
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    static func markdown(for card: CardRecord) -> String {
        var text = formattedText(card)
            .components(separatedBy: "\n")
            .map { line in line.hasPrefix("• ") ? "- " + line.dropFirst(2) : line }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var labels: [String] = []
        if let tag = card.tagColor { labels.append("Tag: \(tag.capitalized)") }
        if card.privacyMode == CardPrivacyMode.spoiler.rawValue { labels.append("Spoiler") }
        if card.privacyMode == CardPrivacyMode.lock.rawValue { labels.append("Locked") }
        if card.isAIGenerated { labels.append("AI") }
        if !labels.isEmpty {
            text += "\n\n*" + labels.joined(separator: " · ") + "*"
        }
        return text
    }

    /// Восстанавливает форматирование так же, как редактор (см.
    /// CardTextView.restoredAttributedString): архив подходит, только если
    /// его голый текст совпадает с text, иначе — обычный текст.
    private static func formattedText(_ card: CardRecord) -> String {
        guard let data = card.formattingData,
              let attributed = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data),
              attributed.string == card.text else {
            return plainText(card.text)
        }

        var result = ""
        let manager = NSFontManager.shared
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttributes(in: fullRange) { attributes, range, _ in
            if attributes[.attachment] is DividerAttachment {
                result += "* * *"
                return
            }
            let chunk = (attributed.string as NSString).substring(with: range)
            let traits = (attributes[.font] as? NSFont).map { manager.traits(of: $0) } ?? []
            let marker: String
            switch (traits.contains(.boldFontMask), traits.contains(.italicFontMask)) {
            case (true, true): marker = "***"
            case (true, false): marker = "**"
            case (false, true): marker = "*"
            case (false, false): marker = ""
            }
            let link = (attributes[.link] as? URL) ?? (attributes[.link] as? String).flatMap(URL.init(string:))
            result += chunk.components(separatedBy: "\n").map { line in
                wrap(line, marker: marker, link: link)
            }.joined(separator: "\n")
        }
        return result
    }

    /// Маркеры ставятся вокруг текста без краевых пробелов — `** bold **`
    /// Markdown не считает жирным.
    private static func wrap(_ line: String, marker: String, link: URL?) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return line }
        let leading = String(line.prefix { $0 == " " })
        let trailing = String(line.reversed().prefix { $0 == " " })
        var core = trimmed
        if let link { core = "[\(core)](\(link.absoluteString))" }
        return leading + marker + core + marker + trailing
    }

    private static func plainText(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FFFC}", with: "* * *")
    }
}
