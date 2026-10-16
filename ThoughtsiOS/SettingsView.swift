import SwiftUI

/// Settings (S7) в MVP: только статус синка с iCloud.
struct SettingsView: View {
    private let sync = CloudSyncSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("iCloud") {
                    LabeledContent("Status", value: sync.status.text)
                    Button("Sync Now") { Task { await CloudSyncEngine.shared.syncNow() } }
                }
                Section {
                    Text("Your Mac and iPhone share the same Thoughts.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
