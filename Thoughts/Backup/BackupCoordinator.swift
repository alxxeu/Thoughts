import AppKit
import UniformTypeIdentifiers

/// Сценарии Export Backup / Import Backup / Export as Markdown — одни и те
/// же из Settings → General и из меню File. Диалоги — обычные NSAlert и
/// NSSavePanel/NSOpenPanel: работают одинаково из любого окна.
///
/// Про заблокированное содержимое (защищённые Spaces и lock-карточки):
/// бэкап всегда полный, шифрование паролем опционально. Но выгрузка
/// заблокированного требует подтвердить владельца Mac (Touch ID/пароль) —
/// иначе экспорт был бы обходом Space Lock. Блокировки защищают устройство,
/// а не секрет автора: на другом Mac они открываются уже его владельцем,
/// поэтому переданный файл защищает только пароль бэкапа.
enum BackupCoordinator {

    // MARK: - Export Backup

    static func exportBackup(viewModel: BoardViewModel) {
        guard !viewModel.isActiveSpaceLocked else { return }
        let snapshot = viewModel.makeSnapshot()
        let locked = snapshot.lockedSummary(passcodeEnabled: viewModel.isSpaceLockEnforced)

        guard !locked.isEmpty else {
            // Без заблокированного — пароль по желанию, галочкой в окне сохранения.
            saveBackup(snapshot, password: nil, offerPasswordCheckbox: true)
            return
        }

        var password: String?
        switch askAboutLockedContent(locked) {
        case .protect:
            guard let chosen = askForNewPassword() else { return }
            password = chosen
        case .dontProtect:
            guard confirmUnprotectedLockedExport() else { return }
        case .cancel:
            return
        }
        authenticateOwner(viewModel, reason: "export locked Spaces and cards") { [password] success in
            guard success else { return }
            saveBackup(snapshot, password: password, offerPasswordCheckbox: false)
        }
    }

    private enum LockedChoice { case protect, dontProtect, cancel }

    private static func askAboutLockedContent(_ locked: BoardSnapshot.LockedSummary) -> LockedChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "This backup includes locked content"
        alert.informativeText = describe(locked)
            + "\n\nLocks apply on the Mac where the backup is imported \u{2014} share the file and its password only with people who may see everything.\n\nProtect this backup with a password?"
        alert.addButton(withTitle: "Protect with Password")
        alert.addButton(withTitle: "Don\u{2019}t Protect")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .protect
        case .alertSecondButtonReturn: return .dontProtect
        default: return .cancel
        }
    }

    private static func confirmUnprotectedLockedExport() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Export without a password?"
        alert.informativeText = "Locked content will be readable by anyone who opens this file."
        alert.addButton(withTitle: "Export Anyway")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func saveBackup(_ snapshot: BoardSnapshot, password: String?, offerPasswordCheckbox: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [BackupCodec.contentType]
        panel.nameFieldStringValue = "Thoughts Backup \(dayStamp()).\(BackupCodec.fileExtension)"
        panel.canCreateDirectories = true

        let checkbox = NSButton(checkboxWithTitle: "Protect with password", target: nil, action: nil)
        if offerPasswordCheckbox {
            panel.accessoryView = paddedAccessory(checkbox)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var password = password
        if offerPasswordCheckbox && checkbox.state == .on {
            guard let chosen = askForNewPassword() else { return }
            password = chosen
        }

        do {
            let data = try BackupCodec.encode(snapshot, password: password)
            try data.write(to: url, options: .atomic)
        } catch {
            showError("Couldn\u{2019}t save the backup", error)
        }
    }

    // MARK: - Import Backup

    static func importBackup(viewModel: BoardViewModel) {
        guard !viewModel.isActiveSpaceLocked else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [BackupCodec.contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let snapshot: BoardSnapshot
        do {
            let data = try Data(contentsOf: url)
            let envelope = try BackupCodec.inspect(data)
            if envelope.isEncrypted {
                guard let decoded = decryptInteractively(data) else { return }
                snapshot = decoded
            } else {
                snapshot = try BackupCodec.decode(data, password: nil)
            }
        } catch {
            showError("Couldn\u{2019}t open the backup", error)
            return
        }

        // Fail-closed: защищённые Spaces без passcode на этом Mac открылись
        // бы кому угодно — сначала пусть будет задан код.
        if snapshot.hasProtectedSpacesWithCards,
           !viewModel.securitySettings.isPasscodeEnabled || !PasscodeStore.hasPasscode {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Set up Space Lock first"
            alert.informativeText = "This backup contains protected Spaces. Turn on a passcode in Settings \u{2192} Security, then import the backup again."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        guard let replacing = askImportMode(snapshot, fileName: url.lastPathComponent, viewModel: viewModel) else { return }

        AutomaticBackups.write(viewModel.makeSnapshot(), reason: "before-import")
        viewModel.applyImported(snapshot, replacing: replacing)

        let alert = NSAlert()
        alert.messageText = "Backup imported"
        alert.informativeText = "\(snapshot.cards.count) card\(snapshot.cards.count == 1 ? "" : "s") \(replacing ? "restored" : "added or updated"). A copy of your previous data was saved automatically."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func decryptInteractively(_ data: Data) -> BoardSnapshot? {
        var message = "Enter the password for this backup."
        while true {
            guard let password = askForExistingPassword(message: message) else { return nil }
            do {
                return try BackupCodec.decode(data, password: password)
            } catch BackupCodec.BackupError.wrongPassword {
                message = "The password is incorrect. Try again."
            } catch {
                showError("Couldn\u{2019}t open the backup", error)
                return nil
            }
        }
    }

    /// true — Replace, false — Add, nil — отмена.
    private static func askImportMode(_ snapshot: BoardSnapshot, fileName: String, viewModel: BoardViewModel) -> Bool? {
        let spaces = Set(snapshot.cards.map(\.workspaceSlot)).count
        let locked = snapshot.lockedSummary(passcodeEnabled: true)
        var summary = "\(spaces) Space\(spaces == 1 ? "" : "s") \u{00B7} \(snapshot.cards.count) card\(snapshot.cards.count == 1 ? "" : "s")"
        let lockedCount = locked.protectedSpaceNames.count + locked.lockedCardCount
        if lockedCount > 0 { summary += " \u{00B7} \(lockedCount) locked" }

        let alert = NSAlert()
        alert.messageText = "Import \u{201C}\(fileName)\u{201D}?"
        alert.informativeText = summary
            + "\n\nAdd merges the backup with your current Spaces and cards. Replace makes Thoughts exactly match the backup."
        alert.addButton(withTitle: "Add to My Thoughts")
        alert.addButton(withTitle: "Replace Everything")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return false
        case .alertSecondButtonReturn:
            let confirm = NSAlert()
            confirm.alertStyle = .critical
            confirm.messageText = "Replace everything?"
            confirm.informativeText = "All current Spaces and cards will be replaced with the backup. A copy of your current data is saved first."
            confirm.addButton(withTitle: "Replace")
            confirm.addButton(withTitle: "Cancel")
            confirm.buttons.first?.hasDestructiveAction = true
            return confirm.runModal() == .alertFirstButtonReturn ? true : nil
        default:
            return nil
        }
    }

    // MARK: - Export as Markdown

    static func exportMarkdown(viewModel: BoardViewModel) {
        guard !viewModel.isActiveSpaceLocked else { return }
        let snapshot = viewModel.makeSnapshot()
        let passcodeEnabled = viewModel.isSpaceLockEnforced
        let locked = snapshot.lockedSummary(passcodeEnabled: passcodeEnabled)

        guard !locked.isEmpty else {
            saveMarkdown(snapshot, includeLocked: false, passcodeEnabled: passcodeEnabled)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Include locked content?"
        alert.informativeText = describe(locked)
            + "\n\nMarkdown files aren\u{2019}t encrypted \u{2014} anyone who opens the file can read everything in it."
        alert.addButton(withTitle: "Exclude Locked")
        alert.addButton(withTitle: "Include Locked")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveMarkdown(snapshot, includeLocked: false, passcodeEnabled: passcodeEnabled)
        case .alertSecondButtonReturn:
            authenticateOwner(viewModel, reason: "export locked Spaces and cards") { success in
                guard success else { return }
                saveMarkdown(snapshot, includeLocked: true, passcodeEnabled: passcodeEnabled)
            }
        default:
            return
        }
    }

    private static func saveMarkdown(_ snapshot: BoardSnapshot, includeLocked: Bool, passcodeEnabled: Bool) {
        let markdown = MarkdownExporter.export(snapshot, includeLocked: includeLocked, passcodeEnabled: passcodeEnabled)
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Nothing to export"
            alert.informativeText = includeLocked
                ? "There are no cards with text yet."
                : "All cards with text are locked. Choose \u{201C}Include Locked\u{201D} to export them."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Thoughts \(dayStamp()).md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try Data(markdown.utf8).write(to: url, options: .atomic)
        } catch {
            showError("Couldn\u{2019}t save the file", error)
        }
    }

    // MARK: - Passwords

    /// Новый пароль с подтверждением; nil — отмена.
    private static func askForNewPassword() -> String? {
        let password = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        password.placeholderString = "Password (at least \(BackupCodec.minimumPasswordLength) characters)"
        let confirmation = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        confirmation.placeholderString = "Confirm password"

        let stack = NSStackView(views: [password, confirmation])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 56)
        // У NSSecureTextField нет собственной ширины — без явного
        // ограничения стек схлопывает поля до пары пикселей.
        for field in [password, confirmation] {
            field.widthAnchor.constraint(equalToConstant: 260).isActive = true
        }

        var message = "You\u{2019}ll need this password to import the backup. If you forget it, the backup can\u{2019}t be recovered."
        while true {
            let alert = NSAlert()
            alert.messageText = "Protect Backup with a Password"
            alert.informativeText = message
            alert.accessoryView = stack
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = password
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }

            if password.stringValue.count < BackupCodec.minimumPasswordLength {
                message = "The password must be at least \(BackupCodec.minimumPasswordLength) characters long."
            } else if password.stringValue != confirmation.stringValue {
                message = "The passwords don\u{2019}t match."
                confirmation.stringValue = ""
            } else {
                return password.stringValue
            }
        }
    }

    private static func askForExistingPassword(message: String) -> String? {
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Password"
        let alert = NSAlert()
        alert.messageText = "This Backup Is Password-Protected"
        alert.informativeText = message
        alert.accessoryView = field
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    // MARK: - Helpers

    private static func authenticateOwner(_ viewModel: BoardViewModel, reason: String, then action: @escaping (Bool) -> Void) {
        viewModel.authenticateWithTouchID(reason: reason) { success in
            if !success {
                let alert = NSAlert()
                alert.messageText = "Authentication failed"
                alert.informativeText = "Locked content can only be exported after confirming it\u{2019}s you."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            action(success)
        }
    }

    private static func describe(_ locked: BoardSnapshot.LockedSummary) -> String {
        var parts: [String] = []
        let spaces = locked.protectedSpaceNames
        if !spaces.isEmpty {
            parts.append("\(spaces.count) locked Space\(spaces.count == 1 ? "" : "s") (\(spaces.joined(separator: ", ")))")
        }
        if locked.lockedCardCount > 0 {
            parts.append("\(locked.lockedCardCount) locked card\(locked.lockedCardCount == 1 ? "" : "s")")
        }
        return "It contains " + parts.joined(separator: " and ") + "."
    }

    private static func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func dayStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Accessory view у NSSavePanel прилипает к краям — даём отступы.
    private static func paddedAccessory(_ view: NSView) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 36))
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }
}
