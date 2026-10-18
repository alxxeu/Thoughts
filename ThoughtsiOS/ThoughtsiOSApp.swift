import SwiftUI

/// Thoughts для iPhone — MVP: лента (S1) и редактор (S2), синк с iCloud.
@main
struct ThoughtsiOSApp: App {
    /// Движок держит доску слабой ссылкой; App живёт всё время работы.
    private let board = BoardModel()

    init() {
        CloudSyncEngine.shared.start(viewModel: board)
        CloudSyncEngine.shared.askInitialSyncChoice = InitialSyncAlert.ask
    }

    var body: some Scene {
        WindowGroup {
            FeedScreen(board: board)
        }
    }
}
