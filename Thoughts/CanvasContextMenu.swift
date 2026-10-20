import SwiftUI
import AppKit

/// Правый клик по пустому месту доски: «New Card» и шаблоны, включённые в
/// Settings → Plugins → Templates (шаблон с вариантами — подменю). Свой
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
            let menu = NSMenu()
            menu.addItem(item(for: .blank, title: CardTemplate.blank.name, at: point))
            let groups = TemplateSettings.shared.enabled
            if !groups.isEmpty {
                menu.addItem(.separator())
                for group in groups {
                    if group.variants.count == 1, let only = group.variants.first {
                        menu.addItem(item(for: only, title: group.menuTitle, at: point))
                    } else {
                        // Несколько вариантов (канбан на 1–4 колонки) — подменю.
                        let submenu = NSMenu()
                        for variant in group.variants {
                            submenu.addItem(item(for: variant, at: point))
                        }
                        let parent = NSMenuItem(title: group.menuTitle, action: nil, keyEquivalent: "")
                        parent.submenu = submenu
                        menu.addItem(parent)
                    }
                }
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        private func item(for template: CardTemplate, title: String? = nil, at point: CGPoint) -> NSMenuItem {
            let item = NSMenuItem(title: title ?? template.menuTitle, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = Pick(template, point)
            return item
        }

        @objc private func pick(_ sender: NSMenuItem) {
            guard let pick = sender.representedObject as? Pick else { return }
            onNewCard?(pick.template, pick.point)
        }
    }
}
