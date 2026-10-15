import SwiftUI

/// Заготовка iPhone-компаньона: пока только проверяет, что общее ядро
/// (Shared/) собирается и читает доску под iOS.
@main
struct ThoughtsiOSApp: App {
    private let workspaces = BoardStore.shared.load().workspaces

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List(workspaces) { Text($0.name) }
                    .navigationTitle("Thoughts")
            }
        }
    }
}
