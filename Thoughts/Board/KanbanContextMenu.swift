import SwiftUI
import AppKit

/// Правый клик по карточке-виджету: «Add Column» / «Remove Column». Свой
/// NSMenu вместо SwiftUI `.contextMenu` — тот пересобирался вместе с каждой
/// перерисовкой, и подменю мигало. Слой прозрачен для всего, кроме правого
/// клика вне плиток и заголовков (там остаётся системное меню поля ввода).
struct KanbanContextMenu: NSViewRepresentable {
    struct Entry {
        var title: String
        var isEnabled = true
        var isDestructive = false
        var action: () -> Void
    }

    /// Точка в координатах слоя (левый верх): попала ли в поле ввода, у которого своё меню.
    var passesThrough: (CGPoint) -> Bool
    var entries: (CGPoint) -> [Entry]

    func makeNSView(context: Context) -> MenuView {
        let view = MenuView()
        view.passesThrough = passesThrough
        view.entries = entries
        return view
    }

    func updateNSView(_ view: MenuView, context: Context) {
        view.passesThrough = passesThrough
        view.entries = entries
    }

    final class MenuView: NSView {
        var passesThrough: ((CGPoint) -> Bool)?
        var entries: ((CGPoint) -> [Entry])?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let isContextClick = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            guard isContextClick else { return nil }
            let local = convert(point, from: superview)
            return passesThrough?(local) == true ? nil : super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) { showMenu(for: event) }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { showMenu(for: event) } else { super.mouseDown(with: event) }
        }

        private final class Action: NSObject {
            let run: () -> Void
            init(_ run: @escaping () -> Void) { self.run = run }
        }

        private func showMenu(for event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard let entries = entries?(point), !entries.isEmpty else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            for entry in entries {
                let item = NSMenuItem(title: entry.title, action: #selector(perform(_:)), keyEquivalent: "")
                item.target = self
                item.isEnabled = entry.isEnabled
                item.representedObject = Action(entry.action)
                menu.addItem(item)
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        @objc private func perform(_ sender: NSMenuItem) {
            (sender.representedObject as? Action)?.run()
        }
    }
}
