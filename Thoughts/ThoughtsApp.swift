import SwiftUI
import AppKit
import CoreSpotlight

@main
struct ThoughtsApp: App {
    // SwiftUI-модификатор .onContinueUserActivity на View ненадёжен для уже
    // запущенного macOS-приложения: ОС переключает фокус на приложение сама,
    // на уровне активации процесса, ещё до того, как SwiftUI пытается
    // доставить саму NSUserActivity — доставка в этот момент часто просто не
    // происходит. Поэтому продолжение Spotlight-активности обрабатываем
    // напрямую через NSApplicationDelegate — единственный гарантированно
    // рабочий на macOS хук для этого случая.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = BoardViewModel()
    @State private var quitGuard = QuitGuard()

    init() {
        // По умолчанию AppKit при зажатии буквенной клавиши в NSTextView
        // показывает попап акцентов вместо повтора символа (как в Safari,
        // TextEdit) — неудобно для карточек с текстом. Отключаем это только
        // для данного приложения (домен defaults этого процесса), глобальную
        // системную настройку не трогаем.
        UserDefaults.standard.register(defaults: ["ApplePressAndHoldEnabled": false])
        appDelegate.viewModel = viewModel
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
            // Заменяет системный пункт Quit (и его Cmd+Q) — см. подробное
            // объяснение почему в QuitGuard.swift.
            CommandGroup(replacing: .appTermination) {
                Button("Quit Thoughts") {
                    quitGuard.handleQuitRequested()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
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

/// Обрабатывает продолжение Spotlight-активности через нативный AppKit-хук.
/// SwiftUI-эквивалент (.onContinueUserActivity на View) на macOS ненадёжен
/// для уже запущенного приложения — см. комментарий в ThoughtsApp.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: BoardViewModel?

    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let cardID = SpotlightIndexer.cardID(from: identifier) else {
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        viewModel?.focusOnCard(id: cardID)
        return true
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
