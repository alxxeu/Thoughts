import AppKit

/// Passcode Space Lock и AI-ключи через iCloud Keychain — сверка при
/// включении синка и при каждом запуске с включённым синком (значение
/// могли поменять на другом Mac). Само хранение — SyncableKeychainItem.
enum KeychainSync {
    static func reconcile(showNotices: Bool) {
        let passcode = PasscodeStore.item.reconcile()
        if case .adoptedFromICloud = passcode {
            // Код пришёл с другого Mac — Space Lock включается и здесь.
            SecuritySettings.shared.isPasscodeEnabled = true
        }

        for provider in [AIProviderKind.openAI, .anthropic] {
            AIKeyStore.item(for: provider).reconcile()
        }
        AISettings.shared.refreshKeyState()

        if showNotices, passcode == .adoptedFromICloud(replacedDifferentValue: true) {
            let alert = NSAlert()
            alert.messageText = "Space Lock passcode updated"
            alert.informativeText = "Space Lock on this Mac now uses the same passcode as your other Mac, synced through iCloud Keychain."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
