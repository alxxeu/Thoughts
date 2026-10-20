import SwiftUI
import AppKit
import CoreSpotlight
import Carbon.HIToolbox

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
    // Не @State: App-структура создаётся один раз за жизнь процесса (в
    // отличие от View), а @State в init() читается ДО того, как SwiftUI
    // его "установит" на реальном хранилище — appDelegate.viewModel ниже
    // получал бы временный бокс вместо той же инстанции, с которой
    // потом работает body. BoardViewModel — @Observable класс, обычного
    // хранимого свойства достаточно для реактивности.
    private let viewModel = BoardViewModel()
    private let quitGuard = QuitGuard()

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
                        WindowBackdrop(settings: viewModel.appearanceSettings)
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
            // Своё меню Format: только то, что хранится в Markdown (системное
            // давало шрифт, цвет и размер, которые терялись бы при сохранении).
            CommandGroup(replacing: .textFormatting) {
                formatButton("Bold", "markdownBold:", "b")
                formatButton("Italic", "markdownItalic:", "i")
                formatButton("Underline", "markdownUnderline:", "u")
                formatButton("Strikethrough", "markdownStrikethrough:", "x", modifiers: [.command, .shift])
                formatButton("Highlight", "markdownHighlight:", "h", modifiers: [.command, .shift])
                Button(FormatCommand.code.title) { FormatCommand.code.send() }
                Button(FormatCommand.link.title) { FormatCommand.link.send() }

                Divider()

                ForEach(FormatCommand.blocks, id: \.self) { command in
                    Button(command.title) { command.send() }
                }

                Divider()

                // Тег карточки, в которой курсор (или открытой в Focus Mode) —
                // см. ContentView, .setCardTag.
                Menu("Tag") {
                    ForEach(Array(CardTagColor.allCases.enumerated()), id: \.element) { index, color in
                        Button(color.rawValue.capitalized) {
                            NotificationCenter.default.post(name: .setCardTag, object: color)
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
                    }
                    Divider()
                    Button("Remove Tag") {
                        NotificationCenter.default.post(name: .setCardTag, object: nil)
                    }
                    .keyboardShortcut("0", modifiers: .control)
                }
            }
            // Само удаление не отсюда — только запрос на подтверждение;
            // см. requestClearSpace/isShowingClearSpaceConfirmation в
            // ContentView, где и происходит реальный вызов
            // clearActiveSpace() после явного "Clear All Cards".
            //
            // .replacing(.newItem), а не .after — WindowGroup сам кладёт в
            // эту группу системный пункт "New Window"/Cmd+N, а приложение
            // однооконное (BoardViewModel/BoardStore — общее состояние):
            // второе окно просто накладывалось бы поверх первого без
            // какого-либо смысла. .replacing убирает его полностью.
            CommandGroup(replacing: .newItem) {
                // Без собственного keyEquivalent: глобальный хоткей Quick
                // Capture (настраивается в Settings → Shortcuts) срабатывает
                // и когда Thoughts активен, второй шорткат в меню задвоил бы его.
                Button("Quick Capture…") {
                    QuickCaptureController.shared.show()
                }
                Divider()
                Button("Export Backup…") {
                    BackupCoordinator.exportBackup(viewModel: viewModel)
                }
                .disabled(viewModel.isActiveSpaceLocked)
                Button("Import Backup…") {
                    BackupCoordinator.importBackup(viewModel: viewModel)
                }
                .disabled(viewModel.isActiveSpaceLocked)
                Button("Export as Markdown…") {
                    BackupCoordinator.exportMarkdown(viewModel: viewModel)
                }
                .disabled(viewModel.isActiveSpaceLocked)
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

                // Toggle: если фокус уже активен — выходит из него, иначе
                // фокусирует карточку с текстовым курсором. Без такой
                // карточки ничего не делает (см. ContentView).
                Button("Focus Card") {
                    NotificationCenter.default.post(name: .toggleFocusCard, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(viewModel.isActiveSpaceLocked || viewModel.desktopOverlay.isDesktopModeActive)
            }
            // Settings — сцена Window, системного пункта "Settings…" у неё нет:
            // ставим свой на место .appSettings. Барьер против побега из
            // заблокированного Space живёт в самом SettingsView
            // (isActiveSpaceLocked → lockedPlaceholder).
            CommandGroup(replacing: .appSettings) {
                Button {
                    SettingsNavigation.shared.open(SettingsNavigation.shared.selectedTab)
                } label: {
                    Label("Settings\u{2026}", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            // .after(.windowArrangement) — стандартная точка вставки
            // приложением своих пунктов в системное меню Window, ниже
            // "Zoom"/"Move Window to..." и разделителя перед списком окон.
            CommandGroup(after: .windowArrangement) {
                Toggle("Desktop Overlay", isOn: Binding(
                    get: { viewModel.desktopOverlay.isEnabled },
                    set: { viewModel.desktopOverlay.isEnabled = $0 }
                ))
            }
            // .after(.help), а не .replacing(.help) — иначе слетает
            // системное поле поиска по меню, которое SwiftUI туда кладёт
            // по умолчанию.
            CommandGroup(after: .help) {
                Button("Replay Onboarding") {
                    NotificationCenter.default.post(name: .replayOnboarding, object: nil)
                }
            }
            CommandMenu("Spaces") {
                // Однонаправленный вход в Desktop mode — не toggle: повторное
                // ⌥D, уже находясь в этом режиме, не делает ничего. Выход —
                // выбор любого Space ниже. Живёт здесь, рядом со Spaces, а не
                // в View: это тоже "куда смотреть" — на карточки или на стол.
                // Есть смысл только в Desktop Overlay, в обычном окне неактивен.
                Button("Show Desktop") {
                    guard !viewModel.desktopOverlay.isDesktopModeActive else { return }
                    viewModel.desktopOverlay.isDesktopModeActive = true
                }
                .keyboardShortcut("d", modifiers: .option)
                .disabled(!viewModel.desktopOverlay.isEnabled)

                Divider()

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
                    // Текущий Space выключен: зажатый ⌥N иначе повторял переход
                    // на автоповторе. Из Desktop mode ⌥N по-прежнему выводит.
                    .disabled(workspace.slot == viewModel.activeSlot && !viewModel.desktopOverlay.isDesktopModeActive)
                }
            }
        }
        // Settings — обычное окно, как у Thaw: сцена Settings центрирует заголовок
        // и рисует пустую полосу тулбара, а Window с .titleBar + .unified даёт
        // заголовок раздела слева в одной строке с кнопками окна.
        Window("Settings", id: SettingsNavigation.windowID) {
            SettingsView(viewModel: viewModel)
                .preferredColorScheme(preferredColorScheme)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentSize)
    }

    /// Пункт Format: действие уходит в карточку с курсором (CardNSTextView);
    /// вне карточки — никто не отвечает, ничего не происходит.
    private func formatButton(_ title: String, _ action: String, _ key: KeyEquivalent, modifiers: SwiftUI.EventModifiers = .command) -> some View {
        Button(title) {
            NSApp.sendAction(Selector(action), to: nil, from: nil)
        }
        .keyboardShortcut(key, modifiers: modifiers)
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
        #if DIRECT
        _ = DirectUpdater.controller // запускает Sparkle и его автопроверку
        #endif
        NSApp.windows.first?.acceptsMouseMovedEvents = true
        if let viewModel {
            QuickCaptureController.shared.start(viewModel: viewModel)
            CloudSyncEngine.shared.start(viewModel: viewModel)
            registerSpaceHotKeys(viewModel)
        }
        interactionMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .leftMouseDown, .rightMouseDown, .otherMouseDown,
                .leftMouseDragged, .rightMouseDragged,
                .keyDown, .scrollWheel, .mouseMoved
            ]
        ) { [weak self] event in
            self?.viewModel?.recordInteraction()
            if event.type == .keyDown, self?.handleSpaceKey(event) == true { return nil }
            return event
        }
        if let unreadable = BoardStore.shared.unreadableFileURL {
            showUnreadableBoardAlert(unreadable)
        }
    }

    /// Текст сохраняется с задержкой (scheduleDebouncedSave) — без этого
    /// последние слова перед ⌘Q/выходом из системы терялись бы. С синком
    /// ещё и отправляем очередь в iCloud, но ждём не дольше 2 с.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        viewModel?.flushPendingSave()
        guard CloudSyncSettings.shared.isEnabled else { return .terminateNow }

        var hasReplied = false
        func reply() {
            guard !hasReplied else { return }
            hasReplied = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        Task {
            await CloudSyncEngine.shared.flushBeforeQuit()
            reply()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { reply() }
        return .terminateLater
    }

    private func showUnreadableBoardAlert(_ url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Thoughts couldn\u{2019}t read your saved cards"
        if url.lastPathComponent == "board.json" {
            alert.informativeText = "The file couldn\u{2019}t be moved aside, so Thoughts won\u{2019}t save anything until it\u{2019}s fixed. "
                + "You can restore a backup with File \u{2192} Import Backup\u{2026}"
        } else {
            alert.informativeText = "The unreadable file was kept as \u{201C}\(url.lastPathComponent)\u{201D}. "
                + "You can restore a backup with File \u{2192} Import Backup\u{2026}"
        }
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Show in Finder")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([url])
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

        showMainWindow()
        viewModel?.focusOnCard(id: cardID)
        return true
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// ⌃⌥1–9 из любого приложения: переключают Space и выводят Thoughts
    /// вперёд. С ⌃, а не голым ⌥, как в меню: глобальный ⌥+цифра забирал
    /// бы эти клавиши у всех приложений (на немецкой раскладке ⌥5–9 печатают
    /// `[ ] | { }`). keyCode — физические клавиши, от раскладки не зависят.
    /// Регистрируются на всё время работы приложения; занятое другим
    /// приложением сочетание просто не сработает.
    /// Из Finder (рабочий стол) хватает и голого ⌥1–9 — см. registerSpaceHotKeys.
    /// ⌥1–9 — здесь, а не только шорткатом пункта меню: через меню каждое
    /// нажатие подсвечивало меню, перерисовывало Space синхронно внутри
    /// подсветки, а на частых нажатиях AppKit ещё и притормаживал повторы —
    /// быстрые переключения копились до «радужного курсора». Отсюда
    /// переключения между кадрами сливаются в одну перерисовку. Пункты меню
    /// остаются — для вида и для клика мышью.
    private func handleSpaceKey(_ event: NSEvent) -> Bool {
        guard let viewModel,
              event.modifierFlags.intersection([.command, .control, .option, .shift]) == .option,
              let slot = Self.digitKeyCodes.firstIndex(of: UInt32(event.keyCode)).map({ $0 + 1 }) else { return false }
        // В тексте ⌥1–9 печатают символы (¡, ™, £…) — как и до перехвата.
        guard !(event.window?.firstResponder is NSTextView) else { return false }
        // Зажатая клавиша (автоповтор) не переключает снова.
        guard !event.isARepeat else { return true }
        let overlay = viewModel.desktopOverlay
        guard slot != viewModel.activeSlot || overlay.isDesktopModeActive else { return true }
        overlay.isDesktopModeActive = false
        NotificationCenter.default.post(name: .switchWorkspace, object: slot)
        return true
    }

    private static let digitKeyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // kVK_ANSI_1...9

    private func registerSpaceHotKeys(_ viewModel: BoardViewModel) {
        for (index, keyCode) in Self.digitKeyCodes.enumerated() {
            let slot = index + 1
            GlobalHotKeyManager.shared.register(keyCode: keyCode, modifiers: UInt32(controlKey | optionKey)) { [weak self] in
                self?.switchSpaceFromHotKey(slot, viewModel: viewModel)
            }
        }

        // Голый ⌥1–9 — только пока впереди Finder (рабочий стол, Desktop
        // mode после клика по иконке): регистрируется при его активации и
        // снимается при уходе, так что в остальных приложениях ⌥+цифра
        // печатает свои символы как обычно.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.updateFinderSpaceHotKeys(finderIsActive: app?.bundleIdentifier == Self.finderBundleID, viewModel: viewModel)
        }
        updateFinderSpaceHotKeys(
            finderIsActive: NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finderBundleID,
            viewModel: viewModel
        )
    }

    private static let finderBundleID = "com.apple.finder"
    private var finderSpaceHotKeys: [HotKeyToken] = []

    private func updateFinderSpaceHotKeys(finderIsActive: Bool, viewModel: BoardViewModel) {
        if finderIsActive {
            guard finderSpaceHotKeys.isEmpty else { return }
            for (index, keyCode) in Self.digitKeyCodes.enumerated() {
                let slot = index + 1
                if case .success(let token) = GlobalHotKeyManager.shared.register(keyCode: keyCode, modifiers: UInt32(optionKey), action: { [weak self] in
                    self?.switchSpaceFromHotKey(slot, viewModel: viewModel)
                }) {
                    finderSpaceHotKeys.append(token)
                }
            }
        } else if !finderSpaceHotKeys.isEmpty {
            GlobalHotKeyManager.shared.unregister(finderSpaceHotKeys)
            finderSpaceHotKeys = []
        }
    }

    private func switchSpaceFromHotKey(_ slot: Int, viewModel: BoardViewModel) {
        let overlay = viewModel.desktopOverlay
        // Уже на этом Space и он на экране — зажатый хоткей ничего не повторяет.
        if slot == viewModel.activeSlot, !overlay.isDesktopModeActive,
           overlay.isEnabled || NSApp.isActive { return }
        // В Overlay окно живёт на уровне стола — активировать нечего,
        // достаточно выйти из Desktop mode.
        if !overlay.isEnabled { showMainWindow() }
        overlay.isDesktopModeActive = false
        NotificationCenter.default.post(name: .switchWorkspace, object: slot)
    }
}

/// Фон главного окна. Ultra Thin Material — живой блюр с наименее заметными
/// швами (BACKLOG «прямоугольные швы»). В fullscreen и Split View под окном
/// чёрный фон отдельного Space, блюр съедает цвет — там ровный цвет из
/// Settings → Appearance → Full Screen.
private struct WindowBackdrop: View {
    var settings: AppearanceSettings
    @State private var isFullScreen = false
    @State private var host = HostWindow()

    var body: some View {
        Group {
            if isFullScreen {
                Color(nsColor: settings.fullScreenBackground.color)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        // Фон пересоздаётся при выходе из Desktop mode — состояние берём у окна.
        .background(HostWindowReader(host: host) { window in
            isFullScreen = window.styleMask.contains(.fullScreen)
        })
        // На willEnter — чтобы цвет был уже во время анимации перехода.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { note in
            if isOwnWindow(note) { isFullScreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            if isOwnWindow(note) { isFullScreen = false }
        }
    }

    /// Окно Settings тоже может уйти в fullscreen — реагируем только на своё.
    private func isOwnWindow(_ note: Notification) -> Bool {
        guard let window = note.object as? NSWindow else { return false }
        return window === host.window
    }

    final class HostWindow {
        weak var window: NSWindow?
    }

    private struct HostWindowReader: NSViewRepresentable {
        let host: HostWindow
        let onResolve: (NSWindow) -> Void

        func makeNSView(context: Context) -> Probe { Probe(host: host, onResolve: onResolve) }
        func updateNSView(_ nsView: Probe, context: Context) {}

        final class Probe: NSView {
            let host: HostWindow
            let onResolve: (NSWindow) -> Void
            init(host: HostWindow, onResolve: @escaping (NSWindow) -> Void) {
                self.host = host
                self.onResolve = onResolve
                super.init(frame: .zero)
            }
            required init?(coder: NSCoder) { fatalError() }
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                host.window = window
                guard let window else { return }
                // Не менять @State посреди обновления вида.
                DispatchQueue.main.async { [onResolve] in onResolve(window) }
            }
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
