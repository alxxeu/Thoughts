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
                        TextField(Workspace.defaultName(forSlot: ws.slot), text: $ws.name)
                            .onChange(of: ws.name) { if ws.name.count > 30 { ws.name = String(ws.name.prefix(30)) } }
                    }
                }
            }
            .navigationTitle("Spaces")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onDisappear {
            // Пустое имя — имя по умолчанию, как при Rename.
            for i in board.workspaces.indices where board.workspaces[i].name.trimmingCharacters(in: .whitespaces).isEmpty {
                board.workspaces[i].name = Workspace.defaultName(forSlot: board.workspaces[i].slot)
            }
            board.saveImmediately()
        }
        .preferredColorScheme(.dark)
    }
}
