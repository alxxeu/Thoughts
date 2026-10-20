import SwiftUI

/// Общее оформление окна настроек (перенесено из Healper): крупный заголовок
/// категории над подзаголовком первой секции, пометка «Soon», тулбар полной высоты
/// и сайдбар, который нельзя схлопнуть.

/// Заголовок первой секции раздела: категория жирным 20 pt и подзаголовок под ней.
struct SettingsHeader: View {
    var category: String?
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let category {
                Text(category)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(.top, 16)
            }
            Text(title)
        }
        .textCase(nil)
    }
}

/// Пометка «Soon» для того, что появится позже.
struct SoonBadge: View {
    var body: some View {
        Text("Soon")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color(nsColor: .quaternarySystemFill)))
    }
}

/// Строка «скоро будет»: приглушённое название, пояснение и «Soon» справа.
struct SoonRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.secondary)
                Text(detail).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer()
            SoonBadge()
        }
    }
}

extension View {
    /// Тулбар полной высоты: без элементов macOS делает строку заголовка ниже, и
    /// кнопки окна уезжают вверх. Невидимый элемент держит высоту.
    func fullHeightToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}

/// Сайдбар нельзя схлопнуть перетаскиванием: SwiftUI возвращает `canCollapse`
/// при каждом обновлении, поэтому запрещаем заново при любом изменении раскладки.
struct SidebarLimits: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) { (nsView as? Probe)?.apply() }

    final class Probe: NSView {
        private var observer: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            DispatchQueue.main.async { [weak self] in
                guard let self, let split = self.splitView else { return }
                self.apply()
                self.observer = NotificationCenter.default.addObserver(
                    forName: NSSplitView.willResizeSubviewsNotification, object: split, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                }
            }
        }

        private var splitView: NSSplitView? {
            var v: NSView? = self
            while let cur = v, !(cur is NSSplitView) { v = cur.superview }
            return v as? NSSplitView
        }

        func apply() {
            guard let ctrl = splitView?.delegate as? NSSplitViewController,
                  let item = ctrl.splitViewItems.first else { return }
            if item.canCollapse { item.canCollapse = false }
            if item.isCollapsed { item.isCollapsed = false }
        }

        isolated deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
