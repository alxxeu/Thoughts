import SwiftUI
import AppKit

/// Settings → General → iCloud: тумблер синка, статус, Sync Now и удаление
/// данных из iCloud. Сам синк — CloudSyncEngine.
struct ICloudSyncSection: View {
    private let settings = CloudSyncSettings.shared
    @State private var isWorking = false

    var body: some View {
        Section {
            Toggle("Sync with iCloud", isOn: Binding(
                get: { settings.isEnabled },
                set: { setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .disabled(!settings.isAvailableInBuild || isWorking)

            if settings.status != .off {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        if settings.status == .syncing || isWorking {
                            ProgressView().controlSize(.small)
                        }
                        Text(statusText)
                            .foregroundStyle(statusIsProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            if settings.isEnabled {
                SettingsRowButton(title: statusIsProblem ? "Try Again" : "Sync Now") {
                    Task { await CloudSyncEngine.shared.syncNow() }
                }
                .disabled(isWorking)
            }

            SettingsRowButton(title: "Delete iCloud Data\u{2026}") {
                confirmDeleteCloudData()
            }
            .disabled(!settings.isAvailableInBuild || isWorking)
        } header: {
            Text("iCloud")
        } footer: {
            Text(settings.isAvailableInBuild
                 ? "Cards, Spaces, tags, locks and formatting sync between your Macs, end-to-end encrypted in your iCloud. The Space Lock passcode and AI keys sync through iCloud Keychain. Appearance stays separate on each Mac."
                 : "iCloud sync isn\u{2019}t available in this build of Thoughts.")
        }
    }

    private var statusText: String {
        switch settings.status {
        case .off: return "Off"
        case .syncing: return "Syncing\u{2026}"
        case .upToDate(let date): return "Up to date \u{00B7} \(date.formatted(date: .omitted, time: .shortened))"
        case .unavailable(let message): return message
        case .failed(let message): return "Couldn\u{2019}t sync: \(message)"
        }
    }

    private var statusIsProblem: Bool {
        switch settings.status {
        case .unavailable, .failed: return true
        default: return false
        }
    }

    private func setEnabled(_ enabled: Bool) {
        isWorking = true
        Task {
            if enabled {
                await CloudSyncEngine.shared.enable()
            } else {
                CloudSyncEngine.shared.disable()
            }
            isWorking = false
        }
    }

    private func confirmDeleteCloudData() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Delete your Thoughts from iCloud?"
        alert.informativeText = "All Spaces and cards stored in iCloud will be deleted and sync will turn off. Cards on this Mac stay as they are. Other Macs keep their own copies but stop syncing."
        alert.addButton(withTitle: "Delete from iCloud")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isWorking = true
        Task {
            _ = await CloudSyncEngine.shared.deleteCloudData()
            isWorking = false
        }
    }
}

/// Settings → General → Backup — те же сценарии, что в меню File (см.
/// BackupCoordinator).
struct BackupSection: View {
    var viewModel: BoardViewModel

    var body: some View {
        Section {
            SettingsRowButton(title: "Export Backup\u{2026}") {
                BackupCoordinator.exportBackup(viewModel: viewModel)
            }
            SettingsRowButton(title: "Import Backup\u{2026}") {
                BackupCoordinator.importBackup(viewModel: viewModel)
            }
            SettingsRowButton(title: "Export as Markdown\u{2026}") {
                BackupCoordinator.exportMarkdown(viewModel: viewModel)
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("A backup contains all your Spaces and cards and can be protected with a password. Markdown is a readable copy for other apps.")
        }
    }
}
