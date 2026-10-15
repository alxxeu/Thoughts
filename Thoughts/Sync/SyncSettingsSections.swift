import SwiftUI
import AppKit

/// Settings → General → iCloud: тумблер синка, статус, Sync Now и удаление
/// данных из iCloud. Сам синк — CloudSyncEngine.
struct ICloudSyncSection: View {
    var viewModel: BoardViewModel
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
                        Text(settings.status.text)
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

    private var statusIsProblem: Bool {
        switch settings.status {
        case .unavailable, .failed: return true
        default: return false
        }
    }

    private func setEnabled(_ enabled: Bool) {
        guard enabled else {
            confirmOwnerIfLocksDependOnSync(reason: "turn off iCloud sync") {
                CloudSyncEngine.shared.disable()
            }
            return
        }
        isWorking = true
        Task {
            await CloudSyncEngine.shared.enable()
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

        confirmOwnerIfLocksDependOnSync(reason: "delete your Thoughts from iCloud") {
            isWorking = true
            Task {
                _ = await CloudSyncEngine.shared.deleteCloudData()
                isWorking = false
            }
        }
    }

    /// Без passcode на этом Mac Space Lock держится только синком (см.
    /// BoardViewModel.isSpaceLockEnforced) — выключение синка открыло бы
    /// защищённые Spaces, поэтому сначала подтверждаем, что это владелец.
    private func confirmOwnerIfLocksDependOnSync(reason: String, then action: @escaping () -> Void) {
        guard viewModel.workspaces.contains(where: \.isProtected),
              !viewModel.securitySettings.isPasscodeEnabled else {
            action()
            return
        }
        viewModel.authenticateWithTouchID(reason: reason) { success in
            if success { action() }
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
