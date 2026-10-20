import SwiftUI
import AppKit

/// Правый клик по пустому месту доски: «New Kanban Card ▸» с шаблонами. Свой
/// NSMenu, а не SwiftUI `.contextMenu` (его пересобирала каждая перерисовка
/// канвы — подменю мигало) и без отслеживания указателя: точку клика даёт
/// само событие. Слой прозрачен для всего, кроме правого клика, — жесты канвы
/// (создание карточки перетаскиванием) работают как раньше.
struct CanvasContextMenu: NSViewRepresentable {
    /// Шаблон и точка клика в координатах канвы.
    var onNewCard: (CardTemplate, CGPoint) -> Void

    func makeNSView(context: Context) -> MenuView {
        let view = MenuView()
        view.onNewCard = onNewCard
        return view
    }

    func updateNSView(_ view: MenuView, context: Context) {
        view.onNewCard = onNewCard
    }

    final class MenuView: NSView {
        var onNewCard: ((CardTemplate, CGPoint) -> Void)?

        /// Как у SwiftUI-канвы: начало координат — слева сверху.
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let isContextClick = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return isContextClick ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) { showMenu(for: event) }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { showMenu(for: event) } else { super.mouseDown(with: event) }
        }

        private final class Pick: NSObject {
            let template: CardTemplate
            let point: CGPoint
            init(_ template: CardTemplate, _ point: CGPoint) { self.template = template; self.point = point }
        }

        private func showMenu(for event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            let submenu = NSMenu()
            for template in CardTemplate.all {
                let item = NSMenuItem(title: template.menuTitle, action: #selector(pick(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = Pick(template, point)
                submenu.addItem(item)
            }
            let parent = NSMenuItem(title: "New Kanban Card", action: nil, keyEquivalent: "")
            parent.submenu = submenu
            let menu = NSMenu()
            menu.addItem(parent)
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        @objc private func pick(_ sender: NSMenuItem) {
            guard let pick = sender.representedObject as? Pick else { return }
            onNewCard?(pick.template, pick.point)
        }
    }
}
