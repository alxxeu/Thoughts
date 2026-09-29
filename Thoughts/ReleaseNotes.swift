import SwiftUI

/// Что нового по версиям — Settings → About → Release Notes. При каждом
/// релизе новая версия добавляется В НАЧАЛО списка `all`.
struct ReleaseNote: Identifiable {
    struct Section: Identifiable {
        let title: String
        let items: [String]
        var id: String { title }
    }

    let version: String
    let sections: [Section]
    var id: String { version }
}

enum ReleaseNotes {
    static let all: [ReleaseNote] = [
        ReleaseNote(version: "1.3", sections: [
            .init(title: "New", items: [
                "iCloud sync \u{2014} your Spaces and cards stay in sync across your Macs, end-to-end encrypted. The Space Lock passcode and AI keys sync through iCloud Keychain.",
                "Quick Capture \u{2014} press \u{2303}\u{2325}\u{2318}N in any app to jot down a card without switching to Thoughts. The shortcut can be changed in Settings \u{2192} Shortcuts.",
                "Backups \u{2014} export all your Spaces and cards to a file, optionally protected with a password, and import them back.",
                "Export as Markdown \u{2014} a readable copy of your notes for other apps.",
                "Ask AI from the right-click menu \u{2014} ask about the selected text or the whole card, then replace it, insert the answer below or copy it.",
                "Customization \u{2014} choose the card font, text size, text color and a background pattern for the canvas in Settings \u{2192} Appearance."
            ]),
            .init(title: "Improved", items: [
                "Pick the AI provider right in any Ask AI panel \u{2014} only the ones ready to use are available.",
                "Ask AI replaces the old AI submenu and the Summarize and Extract buttons with one simple question field.",
                "Show Desktop moved to the Spaces menu, next to the Spaces it switches between."
            ]),
            .init(title: "Fixed", items: [
                "Touch ID prompts now explain what they unlock."
            ])
        ])
    ]
}

/// Список изменений по версиям, новые сверху.
struct ReleaseNotesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(ReleaseNotes.all) { note in
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Version \(note.version)")
                                .font(.system(size: 17, weight: .semibold))
                            ForEach(note.sections) { section in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(section.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    ForEach(section.items, id: \.self) { item in
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text("\u{2022}")
                                                .foregroundStyle(.secondary)
                                            Text(item)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .font(.system(size: 13))
                                    }
                                }
                            }
                        }
                        if note.id != ReleaseNotes.all.last?.id {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 420, height: 440)
    }
}
