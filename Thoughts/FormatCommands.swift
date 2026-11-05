import AppKit

/// Команды Format: один список для меню Format и для правого клика по карточке.
/// Действия уходят по responder chain в CardNSTextView (@objc markdown…);
/// вне карточки никто не отвечает — ничего не происходит.
enum FormatCommand: CaseIterable {
    case bold, italic, underline, strikethrough, highlight, code, link
    case heading1, heading2, heading3, bulletList, numberedList, task, quote, codeBlock, divider

    var title: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        case .highlight: return "Highlight"
        case .code: return "Code"
        case .link: return "Link\u{2026}"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .bulletList: return "Bullet List"
        case .numberedList: return "Numbered List"
        case .task: return "Task"
        case .quote: return "Quote"
        case .codeBlock: return "Code Block"
        case .divider: return "Divider"
        }
    }

    /// Имя @objc-метода CardNSTextView.
    var action: String {
        switch self {
        case .bold: return "markdownBold:"
        case .italic: return "markdownItalic:"
        case .underline: return "markdownUnderline:"
        case .strikethrough: return "markdownStrikethrough:"
        case .highlight: return "markdownHighlight:"
        case .code: return "markdownCode:"
        case .link: return "markdownLink:"
        case .heading1: return "markdownHeading1:"
        case .heading2: return "markdownHeading2:"
        case .heading3: return "markdownHeading3:"
        case .bulletList: return "markdownBulletList:"
        case .numberedList: return "markdownNumberedList:"
        case .task: return "markdownTask:"
        case .quote: return "markdownQuote:"
        case .codeBlock: return "markdownCodeBlock:"
        case .divider: return "markdownDivider:"
        }
    }

    /// Строчные (оборачивают выделение), блочные (меняют строки) — группы меню.
    static let inline: [FormatCommand] = [.bold, .italic, .underline, .strikethrough, .highlight, .code, .link]
    static let blocks: [FormatCommand] = [.heading1, .heading2, .heading3, .bulletList, .numberedList, .task, .quote, .codeBlock, .divider]

    func send() {
        NSApp.sendAction(Selector(action), to: nil, from: nil)
    }

    /// Подменю «Format» для правого клика: действия — прямо в редактор `target`.
    @MainActor
    static func contextMenuItem(target: AnyObject) -> NSMenuItem {
        let submenu = NSMenu(title: "Format")
        func add(_ command: FormatCommand) {
            let item = NSMenuItem(title: command.title, action: Selector(command.action), keyEquivalent: "")
            item.target = target
            submenu.addItem(item)
        }
        inline.forEach(add)
        submenu.addItem(.separator())
        blocks.forEach(add)
        let item = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
        item.submenu = submenu
        return item
    }
}
