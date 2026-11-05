import SwiftUI

/// Settings → Archive: удалённые карточки (30 дней). Вернуть в свой Space или удалить насовсем.
/// Текст spoiler/lock-карточек здесь не показывается.
struct ArchiveSettingsTab: View {
    var viewModel: BoardViewModel
    @State private var isConfirmingEmpty = false

    private static let previewLines = ArchivePreview.maxLines
    private var archive: CardArchive { viewModel.archive }

    var body: some View {
        Form {
            Section {
                if archive.items.isEmpty {
                    Text("No deleted cards")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(archive.items) { item in
                        row(item)
                    }
                }
            } footer: {
                Text("Deleted cards stay here for 30 days, then disappear for good. The Archive lives on this Mac only.")
            }

            if !archive.items.isEmpty {
                Section {
                    SettingsRowButton(title: "Empty Archive\u{2026}") { isConfirmingEmpty = true }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Empty the Archive?", isPresented: $isConfirmingEmpty) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Forever", role: .destructive) { archive.removeAll() }
        } message: {
            Text("\(archive.items.count) card\(archive.items.count == 1 ? "" : "s") will be deleted permanently. This can\u{2019}t be undone.")
        }
    }

    private func row(_ item: ArchivedCard) -> some View {
        let isPrivate = item.record.privacyMode != CardPrivacyMode.none.rawValue
        let spaceName = viewModel.workspaces.first { $0.slot == item.slot }?.name ?? Workspace.defaultName(forSlot: item.slot)
        let days = archive.daysLeft(item)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if isPrivate {
                    Label("Hidden card", systemImage: "lock.fill")
                } else {
                    Text(ArchivePreview.text(item.record.text))
                        .lineLimit(Self.previewLines)
                }
                Text("\(spaceName) \u{00B7} \(days) day\(days == 1 ? "" : "s") left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore") { viewModel.restoreFromArchive(item.id) }
            Button("Delete", role: .destructive) { archive.remove(item.id) }
        }
    }
}

/// Короткий предпросмотр карточки для архива: первые несколько содержательных строк, маркеры
/// Markdown заменены на «•», «☐», «☑» или убраны; разделители и ограждения кода пропущены.
enum ArchivePreview {
    static let maxLines = 4
    private static let maxChars = 200

    static func text(_ markdown: String) -> String {
        var lines: [String] = []
        for raw in markdown.components(separatedBy: "\n") {
            guard let line = clean(raw) else { continue }
            lines.append(line)
            if lines.count == maxLines || lines.joined(separator: "\n").count >= maxChars { break }
        }
        let result = lines.joined(separator: "\n")
        return result.isEmpty ? "Empty card" : String(result.prefix(maxChars))
    }

    /// nil — строку пропускаем (пустая, разделитель, ограждение кода, служебная метка доски).
    private static func clean(_ raw: String) -> String? {
        var line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line == "|| " || line == "||" || line.hasPrefix("```") || line.hasPrefix("::: ") { return nil }
        if line.allSatisfy({ "-*_=\u{2014}".contains($0) }), line.count >= 2 { return nil }
        for (prefix, mark) in [("- [ ] ", "\u{2610} "), ("- [x] ", "\u{2611} "), ("- [X] ", "\u{2611} ")] where line.hasPrefix(prefix) {
            return finish(mark + line.dropFirst(prefix.count))
        }
        if let range = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) { line.removeSubrange(range) }
        else if let range = line.range(of: #"^[-*+]\s+"#, options: .regularExpression) { line.replaceSubrange(range, with: "\u{2022} ") }
        else if let range = line.range(of: #"^>\s?"#, options: .regularExpression) { line.removeSubrange(range) }
        return finish(line)
    }

    private static func finish(_ line: String) -> String? {
        let text = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "~~", with: "")
            .replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}
