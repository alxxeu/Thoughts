import SwiftUI

/// Thoughts для iPhone — MVP: лента (S1) и редактор (S2), синк с iCloud.
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
            FeedScreen(board: board)
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
