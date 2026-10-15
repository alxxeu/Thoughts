import Foundation

/// Читаемая копия заметок в одном Markdown-файле — для других приложений,
/// без обратного импорта (для этого есть .thoughtsbackup).
///
/// Space → `# Имя`, карточки внутри Space идут сверху вниз и слева
/// направо (как их читают на канве) и разделены `---`. Текст карточки уже
/// Markdown; разделитель внутри карточки — `* * *`, чтобы не путать с
/// границей карточек.
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
        var text = MarkdownStyler.parse(card.text)
            .map { $0.block == .divider ? "* * *" : (card.text as NSString).substring(with: $0.range) }
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
}
