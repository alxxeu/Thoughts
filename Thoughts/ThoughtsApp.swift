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
                .background {
                    // В Desktop mode фон тоже должен быть полностью
                    // прозрачным — реальный рабочий стол виден без единого
                    // визуального следа Thoughts поверх него.
                    if !viewModel.desktopOverlay.isDesktopModeActive {
                        VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    }
                }
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
            // Само удаление не отсюда — только запрос на подтверждение;
            // см. requestClearSpace/isShowingClearSpaceConfirmation в
            // ContentView, где и происходит реальный вызов
            // clearActiveSpace() после явного "Clear All Cards".
            CommandGroup(after: .newItem) {
                Divider()
                Button("Clear Space…") {
                    NotificationCenter.default.post(name: .requestClearSpace, object: nil)
                }
                .disabled(viewModel.isActiveSpaceLocked || viewModel.cards.isEmpty)
            }
            CommandGroup(after: .toolbar) {
                Button("Lock Space") {
                    NotificationCenter.default.post(name: .lockCurrentSpace, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!viewModel.securitySettings.isPasscodeEnabled)

                // Однонаправленный вход в Desktop mode — не toggle: повторное
                // ⌥D, уже находясь в этом режиме, не делает ничего. Выход —
                // только через выбор любого Space в CommandMenu ниже.
                Button("Show Desktop") {
                    viewModel.desktopOverlay.isDesktopModeActive = true
                }
                .keyboardShortcut("d", modifiers: .option)
                .disabled(!viewModel.desktopOverlay.isEnabled)
            }
            // Системный пункт "Settings…" (со своей иконкой в App-меню)
            // оставлен как есть — не переопределяем .appSettings отдельной
            // кнопкой без иконки, получался дубль. Барьер против побега из
            // заблокированного Space в Settings всё равно живёт в самом
            // SettingsView (isActiveSpaceLocked → lockedPlaceholder), а не
            // в disabled-состоянии пункта меню — так что убрать дубль можно
            // без потери защиты.
            CommandMenu("Spaces") {
                ForEach(viewModel.workspaces) { workspace in
                    Button(workspace.name) {
                        // Выбор любого Space — единственный способ выйти из
                        // Desktop mode (если он был активен); само
                        // переключение Space не меняется.
                        viewModel.desktopOverlay.isDesktopModeActive = false
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

            // Split View технически реализован через full-screen tiling —
            // размером такого окна жёстко управляет WindowServer. Вызов
            // setFrame здесь либо отклоняется/корректируется системой, либо
            // сам провоцирует новую occlusion-нотификацию, которая заново
            // ставит nudge в очередь — у границы максимального размера
            // Split View это уходило в цикл конкуренции с системным
            // тайлингом (мигание карточек, залипающий курсор). Толгл
            // blendingMode геометрию не трогает и безопасен всегда.
            guard !window.styleMask.contains(.fullScreen) else { return }

            let original = window.frame
            var shifted = original
            shifted.size.width += 1
            window.setFrame(shifted, display: true, animate: false)
            window.setFrame(original, display: true, animate: false)
        }
    }
}
