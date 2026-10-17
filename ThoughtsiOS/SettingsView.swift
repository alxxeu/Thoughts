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

/// Настройки Spaces: имена (до 30 символов, как на Mac) и «Hide empty Spaces».
struct SpaceSettingsView: View {
    @Bindable var board: BoardModel
    @AppStorage("hideEmptySpaces") private var hideEmptySpaces = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Hide empty Spaces", isOn: $hideEmptySpaces)
                } footer: {
                    Text("Spaces without cards don’t show in the bar and the feed. The Space you’re in stays.")
                }
                Section("Names") {
                    ForEach($board.workspaces) { $ws in
                        HStack {
                            TextField(Workspace.defaultName(forSlot: ws.slot), text: $ws.name)
                                .onChange(of: ws.name) { if ws.name.count > Workspace.maxNameLength { ws.name = String(ws.name.prefix(Workspace.maxNameLength)) } }
                            let count = board.cardsByWorkspace[ws.slot]?.count ?? 0
                            Text("^[\(count) Card](inflect: true)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Spaces")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onDisappear {
            // Те же правила, что у Rename: пробелы по краям, пустое — имя по умолчанию.
            for ws in board.workspaces { board.renameWorkspace(slot: ws.slot, to: ws.name) }
        }
        .preferredColorScheme(.dark)
    }
}
