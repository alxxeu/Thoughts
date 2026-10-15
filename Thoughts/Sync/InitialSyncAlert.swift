import AppKit

/// Первое включение синка, когда доска есть и в iCloud, и на этом Mac.
enum InitialSyncAlert {
    static func ask(remote: BoardSnapshot, local: BoardSnapshot) -> InitialSyncChoice {
        let alert = NSAlert()
        alert.messageText = "Your Thoughts are already in iCloud"
        alert.informativeText = "iCloud has \(remote.cards.count) card\(remote.cards.count == 1 ? "" : "s") and this Mac has \(local.cards.count). "
            + "Merge keeps everything from both. A copy of this Mac\u{2019}s data has been saved as a backup."
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Use iCloud")
        alert.addButton(withTitle: "Use This Mac")
        switch alert.runModal() {
        case .alertSecondButtonReturn: return .useCloud
        case .alertThirdButtonReturn: return .useThisDevice
        default: return .merge
        }
    }
}
