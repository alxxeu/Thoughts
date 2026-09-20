import SwiftUI

/// Справочный список всех шорткатов приложения — только для запоминания,
/// сами комбинации фиксированы и не переназначаются (Cmd+Q и
/// Escape-конвенции сюда сознательно не входят, см. EXECUTE.md/BACKLOG.md).
private struct ShortcutInfo: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
}

private let shortcuts: [ShortcutInfo] = [
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
        title: "Show Desktop",
        subtitle: "Enter Desktop Overlay mode, showing your desktop icons.",
        symbol: "\u{2325}D"
    ),
    ShortcutInfo(
        title: "Switch Between Spaces",
        subtitle: "Jump straight to that Space.",
        symbol: "\u{2325}1\u{2013}9"
    )
]

/// Таб Shortcuts в Settings. Правило 4 из EXECUTE.md: у любой новой
/// функции с шорткатом сюда добавляется строка в рамках той же задачи.
struct ShortcutsSettingsTab: View {
    var body: some View {
        Form {
            Section {
                ForEach(shortcuts) { shortcut in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortcut.title)
                            Text(shortcut.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(shortcut.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("These shortcuts are fixed and can\u{2019}t be changed.")
            }
        }
        .formStyle(.grouped)
    }
}
