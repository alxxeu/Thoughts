import SwiftUI

/// Заготовка iPhone-компаньона: доска из iCloud, пока только Spaces с
/// числом карточек и статус синка.
@main
struct ThoughtsiOSApp: App {
    /// Движок держит доску слабой ссылкой; App живёт всё время работы.
    private let board = BoardModel()
    private let sync = CloudSyncSettings.shared
    @State private var enableTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        CloudSyncEngine.shared.start(viewModel: board)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    // Только счётчики: Space Lock на iPhone ещё нет, поэтому
                    // текст карточек (в том числе защищённых Spaces) не показываем.
                    ForEach(board.workspaces) { workspace in
                        LabeledContent(workspace.name, value: "\(board.cardsByWorkspace[workspace.slot]?.count ?? 0)")
                    }
                    Section {
                        Text(sync.status.text)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Thoughts")
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            enableSyncIfNeeded(phase)
        }
    }

    /// На iPhone синк всегда включён: компаньон без него пуст. Если iCloud
    /// был недоступен, пробуем снова при каждом возвращении в приложение.
    private func enableSyncIfNeeded(_ phase: ScenePhase) {
        guard phase == .active, !sync.isEnabled, enableTask == nil else { return }
        enableTask = Task {
            await CloudSyncEngine.shared.enable()
            enableTask = nil
        }
    }
}
