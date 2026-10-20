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
    /// Короткая версия для карточки What’s new — канбан-доской: колонка на раздел,
    /// плитка на пункт (простой текст, без Markdown). nil — карточка-текст.
    var board: [Section]? = nil
    var id: String { version }
}

enum ReleaseNotes {
    static let all: [ReleaseNote] = [
        ReleaseNote(version: "1.5", sections: [
            .init(title: "New", items: [
                "**Kanban cards** \u{2014} right-click an empty spot on the board and choose New Kanban Card with 1 to 4 columns. Add tiles, drag them between columns, hold the check to finish one.",
                "**New Card** in the same right-click menu.",
                "**All Spaces at a glance** \u{2014} hold \u{2325} and press Tab to see every Space with a map of its cards, release to jump there. From other apps: \u{2303}\u{2325}Tab.",
                "**Next and previous Space** with \u{2325}\u{2190} and \u{2325}\u{2192}.",
                "**\u{2325}1\u{2013}9 from the desktop** \u{2014} switch Spaces right after clicking the desktop.",
                "**Customize the Space bar** \u{2014} hover it, click the gear, then hide icons or drag them into your own order.",
                "**More AI providers** \u{2014} Google Gemini, OpenRouter, Groq, Mistral and Ollama, plus an option to turn AI off.",
                "**Format menu** with every Markdown style, also in the right-click menu of a card."
            ]),
            .init(title: "Improved", items: [
                "A new **Settings** window with a sidebar.",
                "**Appearance** previews cards over your desktop, remembers your last three custom colors and lets you pick a background color for full screen.",
                "A lighter window background with fewer blur artifacts.",
                "**Desktop Overlay** stays in place when you show the desktop with a hot corner or a gesture."
            ]),
            .init(title: "Fixed", items: [
                "The cursor no longer jumps around Markdown headings and checklists.",
                "Hidden Markdown characters no longer show through a selection.",
                "Links typed without https:// open correctly."
            ])
        ], board: [
            .init(title: "New", items: [
                "Kanban cards",
                "New Card in the right-click menu",
                "All Spaces \u{2014} hold \u{2325}, press Tab",
                "\u{2325}\u{2190} \u{2325}\u{2192} \u{2014} next Space",
                "\u{2325}1\u{2013}9 from the desktop",
                "Customizable Space bar",
                "More AI providers",
                "Format menu"
            ]),
            .init(title: "Improved", items: [
                "New Settings window",
                "Appearance preview on your desktop",
                "Last three custom colors",
                "Full-screen background color",
                "Lighter window background",
                "Desktop Overlay stays on Show Desktop"
            ]),
            .init(title: "Fixed", items: [
                "Cursor jumps in Markdown",
                "Hidden characters in a selection",
                "Links without https://"
            ])
        ]),
        ReleaseNote(version: "1.4", sections: [
            .init(title: "New", items: [
                "**Markdown** \u{2014} write cards in Markdown: headings, **bold**, *italic*, ~underline~, ~~strikethrough~~, ==highlight==, `code`, links and lists. The formatting characters show next to the cursor and hide everywhere else. Markdown pasted from Notion and other apps arrives formatted.",
                "**Task lists, quotes and code blocks** \u{2014} check off tasks with a click and copy a code block with one button.",
                "**AI answers** arrive formatted in Markdown.",
                "**Tags from the keyboard** \u{2014} \u{2303}1\u{2013}7 color the card you\u{2019}re editing, \u{2303}0 removes the tag.",
                "**Switch Spaces from any app** with \u{2303}\u{2325}1\u{2013}9 \u{2014} Thoughts comes forward on that Space.",
                "A redesigned **Shortcuts** section in Settings, with an example of every Markdown style.",
                "**What\u{2019}s new** after an update, and **Check for Updates** in Settings \u{2192} About."
            ]),
            .init(title: "Improved", items: [
                "Improved everything we could \u{2014} *faster, smoother and more reliable*.",
                "Improved security."
            ]),
            .init(title: "Note", items: [
                "Update Thoughts on all your Macs: older versions show Markdown characters in cards edited here. Your cards were converted automatically, and a copy of the previous data is kept in the Backups folder.",
                "Thoughts has a new text engine, so some elements in existing cards may look a little different."
            ])
        ]),
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
                                            // Пункты — в Markdown карточек (для What’s new), здесь без разметки.
                                            Text(MarkdownStyler.plainText(item))
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

/// Плашка «What’s new» после обновления — см. SpaceToolbar.whatsNewBanner.
enum WhatsNew {
    private static let lastSeenKey = "whatsNew.lastSeenVersion"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Заметка текущей версии, если её ещё не показывали. Первая установка
    /// (тур не пройден, версии не помнили) — не обновление: там онбординг,
    /// версию просто запоминаем. Тур пройден, а версии нет — это
    /// пользователь версии до появления плашки, ему показываем.
    static func pendingNote(
        defaults: UserDefaults = .standard,
        version: String = currentVersion,
        hasCompletedTour: Bool = OnboardingState.hasCompletedTour
    ) -> ReleaseNote? {
        let lastSeen = defaults.string(forKey: lastSeenKey)
        if lastSeen == nil, !hasCompletedTour {
            defaults.set(version, forKey: lastSeenKey)
            return nil
        }
        guard lastSeen != version else { return nil }
        return ReleaseNotes.all.first { $0.version == version }
    }

    static func markSeen(defaults: UserDefaults = .standard, version: String = currentVersion) {
        defaults.set(version, forKey: lastSeenKey)
    }

    /// Текст карточки What’s new: канбан-доска, если у заметки есть `board`,
    /// иначе Markdown-текст.
    static func cardText(for note: ReleaseNote) -> String {
        guard let board = note.board else { return markdown(for: note) }
        let columns = board.map { section in
            (["## \(section.title)"] + section.items.map { "- \($0)" }).joined(separator: "\n")
        }
        return (["::: board"] + [columns.joined(separator: "\n||\n")]).joined(separator: "\n")
    }

    /// Размер карточки What’s new: доска — по 4 клетки на колонку, высота по
    /// самой длинной колонке; текст — как раньше.
    static func cardSize(for note: ReleaseNote) -> CGSize {
        guard let board = note.board else { return CGSize(width: 360, height: 440) }
        let step = BoardViewModel.cardSizeStep, gap = BoardViewModel.cardGap
        let columns = min(24, max(2, board.count * 4))
        let rows = min(14, max(6, (board.map(\.items.count).max() ?? 0) + 2))
        return CGSize(width: CGFloat(columns) * step - gap, height: CGFloat(rows) * step - gap)
    }

    /// Текст карточки с заметкой — обычный Markdown карточек: разделы через
    /// разделитель, Note — цитатой.
    static func markdown(for note: ReleaseNote) -> String {
        let sections = note.sections.map { section in
            // Цитата сама говорит, что это заметка, — без заголовка.
            section.title == "Note"
                ? section.items.map { "> \($0)" }.joined(separator: "\n")
                : (["## \(section.title)"] + section.items.map { "- \($0)" }).joined(separator: "\n")
        }
        return "# What\u{2019}s new in \(note.version)\n\n" + sections.joined(separator: "\n\n--\n\n")
    }
}
