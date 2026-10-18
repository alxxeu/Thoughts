import UIKit

/// Первое включение синка, когда доска есть и в iCloud, и на этом iPhone — тот же выбор
/// и те же слова, что у Mac (Thoughts/Sync/InitialSyncAlert.swift).
@MainActor
enum InitialSyncAlert {
    static func ask(remote: BoardSnapshot, local: BoardSnapshot) async -> InitialSyncChoice {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "Your Thoughts are already in iCloud",
                message: "iCloud has \(remote.cards.count) card\(remote.cards.count == 1 ? "" : "s") and this iPhone has \(local.cards.count). "
                    + "Merge keeps everything from both. A copy of this iPhone\u{2019}s data has been saved as a backup. "
                    + "Use This iPhone deletes the cards that are only in iCloud.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Merge", style: .default) { _ in continuation.resume(returning: .merge) })
            alert.addAction(UIAlertAction(title: "Use iCloud", style: .default) { _ in continuation.resume(returning: .useCloud) })
            alert.addAction(UIAlertAction(title: "Use This iPhone", style: .destructive) { _ in continuation.resume(returning: .useThisDevice) })
            guard var top = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else {
                continuation.resume(returning: .merge)
                return
            }
            while let presented = top.presentedViewController { top = presented }
            top.present(alert, animated: true)
        }
    }
}
