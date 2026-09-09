import AppKit
import SwiftUI

/// Требует повторного Cmd+Q в течение короткого окна, прежде чем реально
/// закрыть приложение — защита от случайного выхода.
///
/// Важно: это НЕ перехват события клавиатуры. Горячие клавиши, привязанные
/// к пунктам меню (в т.ч. системный "Quit", который SwiftUI создаёт
/// автоматически), обрабатываются AppKit через performKeyEquivalent ещё до
/// того, как событие дошло бы до локального NSEvent-монитора — поэтому
/// такой перехват в принципе не сработал бы для Cmd+Q. Вместо этого сам
/// системный пункт Quit заменяется через
/// `CommandGroup(replacing: .appTermination)` в ThoughtsApp.swift на кнопку,
/// вызывающую `handleQuitRequested()` — так что для Cmd+Q это буквально
/// единственный код, который вообще выполняется.
///
/// Первый вызов показывает нативный HUD-баннер (тот же приём, что у
/// системных оверлеев громкости/яркости: NSVisualEffectView с материалом
/// .hudWindow) и не завершает приложение. Если второй вызов происходит в
/// течение отведённого времени — приложение закрывается по-настоящему; если
/// нет — состояние сбрасывается и баннер прячется.
final class QuitGuard {
    private static let armDuration: TimeInterval = 2.0
    private static let panelSize = NSSize(width: 260, height: 76)

    private var isArmed = false
    private var resetTask: DispatchWorkItem?
    private lazy var panel: NSPanel = Self.makePanel()

    /// Вызывается из замещающей кнопки Quit в ThoughtsApp.swift.
    func handleQuitRequested() {
        if isArmed {
            disarm(hidingPanel: true)
            NSApp.terminate(nil)
            return
        }

        arm()
    }

    private func arm() {
        isArmed = true
        showPanel()

        let task = DispatchWorkItem { [weak self] in
            self?.disarm(hidingPanel: true)
        }
        resetTask?.cancel()
        resetTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.armDuration, execute: task)
    }

    private func disarm(hidingPanel: Bool) {
        isArmed = false
        resetTask?.cancel()
        resetTask = nil
        if hidingPanel {
            hidePanel()
        }
    }

    // MARK: - HUD-панель

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        // .fullScreenAuxiliary — чтобы баннер мог показаться поверх окна
        // Thoughts, даже когда оно развёрнуто в системный fullscreen.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let hosting = NSHostingView(rootView: QuitBannerView())
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hosting

        return panel
    }

    private func showPanel() {
        positionPanel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hidePanel() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }

    /// По центру экрана с активным ключевым окном (или главного экрана как
    /// fallback), в верхней трети — там, где обычно и появляются подобные
    /// системные подсказки, не перекрывая контент карточек по центру.
    private func positionPanel() {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let screenFrame = screen.visibleFrame
        let size = Self.panelSize
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height - 24
        )
        panel.setFrameOrigin(origin)
    }
}

/// Содержимое HUD-баннера — в стиле системных оверлеев macOS.
private struct QuitBannerView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Quit Thoughts?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Press ⌘Q again to quit")
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(width: 260)
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow))
        .clipShape(Capsule())
    }
}
