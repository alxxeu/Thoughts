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
    private let settings = QuickCaptureSettings.shared
    @State private var quickCaptureError: String?

    var body: some View {
        Form {
            quickCaptureSection

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
                Text("Other shortcuts are fixed and can\u{2019}t be changed.")
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
        } footer: {
            if let quickCaptureError {
                Text(quickCaptureError)
                    .foregroundStyle(.red)
            } else {
                Text("Works from any app. Click the shortcut to record a new one; Delete restores \(HotKeyShortcut.quickCaptureDefault.displayString).")
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
