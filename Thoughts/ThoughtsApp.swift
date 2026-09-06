import SwiftUI
import AppKit

@main
struct ThoughtsApp: App {
    @State private var viewModel = BoardViewModel()

    init() {
        // По умолчанию AppKit при зажатии буквенной клавиши в NSTextView
        // показывает попап акцентов вместо повтора символа (как в Safari,
        // TextEdit) — неудобно для карточек с текстом. Отключаем это только
        // для данного приложения (домен defaults этого процесса), глобальную
        // системную настройку не трогаем.
        UserDefaults.standard.register(defaults: ["ApplePressAndHoldEnabled": false])
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
                .ignoresSafeArea()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            TextFormattingCommands()
            CommandMenu("Spaces") {
                ForEach(viewModel.workspaces) { workspace in
                    Button(workspace.name) {
                        NotificationCenter.default.post(name: .switchWorkspace, object: workspace.slot)
                    }
                    .keyboardShortcut(
                        KeyEquivalent(Character("\(workspace.slot)")),
                        modifiers: .option
                    )
                }
            }
        }
        Settings {
            SettingsView()
        }
    }
}

// Вспомогательный ViewRepresentable для использования размытия AppKit
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active

        // Единственное, что реально и стабильно чинит пропавший
        // .behindWindow-фон, — это фактическая смена геометрии окна (выход
        // из fullscreen и обратно). state (.active/.followsWindowActiveState)
        // тут ни при чём — подложка переприкрепляется к бэкинг-стору окна
        // только при настоящем relayout. Поэтому вместо isHidden-тогла
        // (не трогает геометрию, не помогал) — короткий nudge реального
        // фрейма окна на 1pt туда-обратно, без анимации: та же суть, что и
        // переключение fullscreen, но незаметно для глаза.
        for name: Notification.Name in [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didBecomeKeyNotification,
            NSApplication.didBecomeActiveNotification
        ] {
            context.coordinator.observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak visualEffectView] _ in
                    context.coordinator.nudge(visualEffectView?.window)
                }
            )
        }
        context.coordinator.observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak visualEffectView] _ in
                context.coordinator.nudge(visualEffectView?.window)
            }
        )

        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleNSView(_ nsView: NSVisualEffectView, coordinator: Coordinator) {
        for observer in coordinator.observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    final class Coordinator {
        var observers: [NSObjectProtocol] = []
        private var isNudging = false

        func nudge(_ window: NSWindow?) {
            guard let window, !isNudging else { return }
            isNudging = true
            let original = window.frame
            var shifted = original
            shifted.size.width += 1
            window.setFrame(shifted, display: true, animate: false)
            window.setFrame(original, display: true, animate: false)
            isNudging = false
        }
    }
}
