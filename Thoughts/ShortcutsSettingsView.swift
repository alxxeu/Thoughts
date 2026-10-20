import SwiftUI

/// Справочный список шорткатов приложения — только для запоминания, эти
/// комбинации фиксированы и не переназначаются (Cmd+Q и Escape-конвенции
/// сюда сознательно не входят, см. EXECUTE.md/BACKLOG.md). Единственное
/// исключение — глобальный хоткей Quick Capture, у него своя секция с
/// рекордером (см. ShortcutsSettingsTab.quickCaptureSection).
private struct ShortcutInfo: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
}

private let generalShortcuts: [ShortcutInfo] = [
    ShortcutInfo(
        title: "Lock Space",
        subtitle: "Instantly protect and lock the active Space.",
        symbol: "\u{2318}L"
    ),
    ShortcutInfo(
        title: "Focus Card",
        subtitle: "Hide every other card and focus on the one you\u{2019}re editing.",
        symbol: "\u{2318}F"
    ),
    ShortcutInfo(
        title: "Tag Card",
        subtitle: "Color the card you\u{2019}re editing: red, orange, yellow, green, blue, indigo, purple.",
        symbol: "\u{2303}1\u{2013}7"
    ),
    ShortcutInfo(
        title: "Remove Tag",
        subtitle: "Clear the tag of the card you\u{2019}re editing.",
        symbol: "\u{2303}0"
    ),
    ShortcutInfo(
        title: "Switch Between Spaces",
        subtitle: "Jump straight to that Space.",
        symbol: "\u{2325}1\u{2013}9"
    ),
    ShortcutInfo(
        title: "Switch Spaces from Any App",
        subtitle: "Jumps to that Space and brings Thoughts forward.",
        symbol: "\u{2303}\u{2325}1\u{2013}9"
    ),
    ShortcutInfo(
        title: "Show Desktop",
        subtitle: "Enter Desktop Overlay mode, showing your desktop icons. Works from any app.",
        symbol: "\u{2325}D"
    ),
    ShortcutInfo(
        title: "Show Desktop from Any App",
        subtitle: "Same as \u{2325}D, in case another app uses it.",
        symbol: "\u{2303}\u{2325}D"
    )
]

/// Строка Markdown: что сделать (клавиши или что набрать) и как это будет
/// выглядеть в карточке.
private struct MarkdownExample: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    var symbol: String?
    let preview: AnyView
}

private let formatExamples: [MarkdownExample] = [
    MarkdownExample(title: "Bold", subtitle: "Wraps the selection in **\u{2026}**.", symbol: "\u{2318}B",
                    preview: AnyView(Text("Bold").bold())),
    MarkdownExample(title: "Italic", subtitle: "Wraps the selection in *\u{2026}*.", symbol: "\u{2318}I",
                    preview: AnyView(Text("Italic").italic())),
    MarkdownExample(title: "Underline", subtitle: "Wraps the selection in ~\u{2026}~.", symbol: "\u{2318}U",
                    preview: AnyView(Text("Underline").underline())),
    MarkdownExample(title: "Strikethrough", subtitle: "Wraps the selection in ~~\u{2026}~~.", symbol: "\u{21E7}\u{2318}X",
                    preview: AnyView(Text("Strike").strikethrough())),
    MarkdownExample(title: "Highlight", subtitle: "Wraps the selection in ==\u{2026}==.", symbol: "\u{21E7}\u{2318}H",
                    preview: AnyView(Text("Highlight").padding(.horizontal, 2).background(Color.yellow.opacity(0.35))))
]

private let typeExamples: [MarkdownExample] = [
    MarkdownExample(title: "Heading", subtitle: "# , ## or ### and a space at the start of a line.",
                    preview: AnyView(Text("Heading").font(.system(size: 15, weight: .bold)))),
    MarkdownExample(title: "List", subtitle: "- and a space; 1. for a numbered list.",
                    preview: AnyView(Text("\u{2022}  Item"))),
    MarkdownExample(title: "Task", subtitle: "[] and a space. Click the box to check it.",
                    preview: AnyView(HStack(spacing: 6) {
                        Image(systemName: "square")
                        Text("Task")
                    })),
    MarkdownExample(title: "Quote", subtitle: "> and a space.",
                    preview: AnyView(HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1).fill(Color.accentColor).frame(width: 3, height: 16)
                        Text("Quote")
                    })),
    MarkdownExample(title: "Code", subtitle: "`code` inside a line; ``` on its own line for a block.",
                    preview: AnyView(Text("code").font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4)))),
    MarkdownExample(title: "Link", subtitle: "[text](https://\u{2026}) or just paste an address.",
                    preview: AnyView(Text("Link").foregroundStyle(Color.accentColor).underline())),
    MarkdownExample(title: "Divider", subtitle: "A line of two to ten dashes: --",
                    preview: AnyView(Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 60, height: 1)))
]

/// Таб Shortcuts в Settings. Правило 4 из EXECUTE.md: у любой новой
/// функции с шорткатом сюда добавляется строка в рамках той же задачи.
struct ShortcutsSettingsTab: View {
    private let settings = QuickCaptureSettings.shared
    @State private var quickCaptureError: String?

    var body: some View {
        Form {
            quickCaptureSection

            Section("General") {
                ForEach(generalShortcuts) { shortcut in
                    row(shortcut.title, shortcut.subtitle, symbol: shortcut.symbol)
                }
            }

            Section {
                ForEach(formatExamples) { example in
                    row(example.title, example.subtitle, preview: example.preview, symbol: example.symbol)
                }
            } header: {
                Text("Markdown \u{2014} Format")
            } footer: {
                Text("Press again to remove the formatting.")
            }

            Section {
                ForEach(typeExamples) { example in
                    row(example.title, example.subtitle, preview: example.preview)
                }
            } header: {
                Text("Markdown \u{2014} Type")
            } footer: {
                Text("Markdown characters show while you edit a line and hide when you move on. Other shortcuts are fixed and can\u{2019}t be changed.")
            }
        }
        .formStyle(.grouped)
    }

    private var quickCaptureSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.isEnabled },
                set: { enabled in
                    settings.isEnabled = enabled
                    report(QuickCaptureController.shared.updateHotKey())
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Capture")
                    Text("Jot down a card from any app without switching to Thoughts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            LabeledContent("Shortcut") {
                ShortcutRecorderView(
                    shortcut: settings.shortcut,
                    onRecord: { report(QuickCaptureController.shared.apply($0)) },
                    onReset: { report(QuickCaptureController.shared.apply(.quickCaptureDefault)) },
                    onRecordingChange: { recording in
                        if recording {
                            quickCaptureError = nil
                            QuickCaptureController.shared.suspendHotKey()
                        } else {
                            QuickCaptureController.shared.updateHotKey()
                        }
                    }
                )
            }
            .disabled(!settings.isEnabled)
        } header: {
            SettingsHeader(category: "Shortcuts", title: "Quick Capture")
        } footer: {
            if let quickCaptureError {
                Text(quickCaptureError)
                    .foregroundStyle(.red)
            } else {
                Text("Works from any app. Click the shortcut to record a new one; Delete restores \(HotKeyShortcut.quickCaptureDefault.displayString).")
            }
        }
    }

    private func row(_ title: String, _ subtitle: String, preview: AnyView? = nil, symbol: String? = nil) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let preview {
                preview
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
            if let symbol {
                Text(symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
    }

    private func report(_ error: GlobalHotKeyManager.RegistrationError?) {
        switch error {
        case nil:
            quickCaptureError = nil
        case .alreadyInUse:
            quickCaptureError = "This shortcut is already used by another app. Try a different one."
        case .failed:
            quickCaptureError = "This shortcut couldn\u{2019}t be registered. Try a different one."
        }
    }
}
