import AppKit

/// «Save as Template…» в правом клике карточки: спрашивает имя и комментарий и
/// кладёт шаблон в папку своих шаблонов (текст, размер и тег — из карточки).
@MainActor
enum SaveTemplatePrompt {
    static func run(for card: Card) {
        let alert = NSAlert()
        alert.messageText = "Save as Template"
        alert.informativeText = "It will appear when you right-click an empty spot on the board."

        let nameField = NSTextField(frame: NSRect(x: 0, y: 32, width: 280, height: 24))
        nameField.placeholderString = "Name"
        nameField.stringValue = suggestedName(for: card.text)
        let noteField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        noteField.placeholderString = "Note (optional)"
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 56))
        fields.addSubview(nameField)
        fields.addSubview(noteField)
        alert.accessoryView = fields
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = nameField
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let template = UserTemplate(name: name, note: noteField.stringValue, text: card.text, size: card.size, tag: card.tagColor)
        do {
            try UserTemplateStore.shared.add(template)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Couldn\u{2019}t save the template"
            failure.informativeText = error.localizedDescription
            failure.runModal()
        }
    }

    /// Имя по умолчанию — первая содержательная строка карточки без разметки.
    static func suggestedName(for text: String) -> String {
        let plain = MarkdownStyler.plainText(text)
        let line = plain.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "Template"
        return String(line.prefix(40))
    }
}
