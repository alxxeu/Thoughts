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
    @Environment(\.openSettings) private var openSettings

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
                .preferredColorScheme(preferredColorScheme)
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
            CommandGroup(after: .toolbar) {
                Button("Lock Space") {
                    NotificationCenter.default.post(name: .lockCurrentSpace, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!viewModel.securitySettings.isPasscodeEnabled)
            }
            // Настройки могут ослабить/сменить способ разблокировки — из
            // заблокированного Space нельзя сбежать в Settings и таким
            // образом обойти lock screen. .disabled() на командах меню
            // ненадёжен как единственная защита (может не обновиться
            // мгновенно), поэтому основной барьер — в самом SettingsView.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(viewModel.isActiveSpaceLocked)
            }
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
            SettingsView(viewModel: viewModel)
                .preferredColorScheme(preferredColorScheme)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch viewModel.appearanceSettings.colorScheme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

}

/// Обрабатывает продолжение Spotlight-активности через нативный AppKit-хук.
/// SwiftUI-эквивалент (.onContinueUserActivity на View) на macOS ненадёжен
/// для уже запущенного приложения — см. комментарий в ThoughtsApp.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: BoardViewModel?
    private var interactionMonitor: Any?

    /// Единая точка сброса idle-таймера Space Lock: один NSEvent-монитор
    /// на всё приложение вместо разбросанных вызовов по компонентам —
    /// ловит клики, драги, ввод текста, скролл и движение мыши
    /// централизованно, независимо от того, какой конкретно View/NSView
    /// их обработал.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.windows.first?.acceptsMouseMovedEvents = true
        interactionMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .leftMouseDown, .rightMouseDown, .otherMouseDown,
                .leftMouseDragged, .rightMouseDragged,
                .keyDown, .scrollWheel, .mouseMoved
            ]
        ) { [weak self] event in
            self?.viewModel?.recordInteraction()
            return event
        }
    }

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
        context.coordinator.visualEffectView = visualEffectView

        // И геометрический nudge окна, и одиночный тогл blendingMode
        // срабатывают через раз: уведомление приходит раньше, чем
        // WindowServer реально заканчивает переход между Spaces, и
        // последующая анимация иногда переигрывает фикс обратно в
        // сломанное состояние. Поэтому не чиним сразу, а с небольшой
        // задержкой после последнего уведомления (когда переход уже
        // точно завершился), и сразу обоими приёмами вместе.
        for name: Notification.Name in [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didBecomeKeyNotification,
            NSApplication.didBecomeActiveNotification
        ] {
            context.coordinator.observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                    context.coordinator.scheduleNudge()
                }
            )
        }
        context.coordinator.observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                context.coordinator.scheduleNudge()
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
        weak var visualEffectView: NSVisualEffectView?
        private var pendingNudge: DispatchWorkItem?

        func scheduleNudge() {
            pendingNudge?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.performNudge()
            }
            pendingNudge = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }

        private func performNudge() {
            guard let view = visualEffectView, let window = view.window else { return }
            view.blendingMode = .withinWindow
            view.blendingMode = .behindWindow

            let original = window.frame
            var shifted = original
            shifted.size.width += 1
            window.setFrame(shifted, display: true, animate: false)
            window.setFrame(original, display: true, animate: false)
        }
    }
}
