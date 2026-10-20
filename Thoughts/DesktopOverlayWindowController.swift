import AppKit
import Carbon.HIToolbox

/// Окно Thoughts в режиме Desktop Overlay: уровень над иконками стола,
/// безрамочный фрейм во весь экран, глобальные хоткеи ⌥D/⌃⌥D/⌃⌥1–9 — и
/// возврат обычного окна при выключении. Чистый AppKit, состояние берёт из
/// DesktopOverlaySettings; ContentView только отдаёт окно и зовёт apply().
final class DesktopOverlayWindowController {
    private let settings = DesktopOverlaySettings.shared
    /// Конкретно окно, хостящее канву (не Settings/QuitGuard), — см.
    /// WindowAccessor; NSApp.keyWindow ненадёжен, Settings-окно может быть
    /// открыто и в фокусе ровно в момент переключения тумблера.
    private weak var window: NSWindow?
    /// Фрейм окна до включения режима — вернуть его ровно как было.
    private var savedWindowFrame: NSRect?
    private var observers: [NSObjectProtocol] = []
    private var isActivationPendingFullScreenExit = false
    /// Только хоткеи Desktop Overlay — снимаются при его выключении, не
    /// трогая глобальный хоткей Quick Capture (см. GlobalHotKeyManager).
    private var hotKeyTokens: [HotKeyToken] = []

    func attach(_ window: NSWindow) {
        guard self.window == nil else { return }
        self.window = window
        allowWindowToBecomeKey(window)
        apply()
        // AppKit иногда сам переигрывает styleMask/title окна на
        // переходах фокуса (например, relock() Space Lock делает
        // makeFirstResponder(nil)) — тот же класс проблемы, что уже
        // решён для VisualEffectBlur в ThoughtsApp.swift через
        // переприменение после нотификаций, а не один раз. Здесь —
        // то же самое для chrome-настроек Desktop Overlay.
        for name: Notification.Name in [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didChangeOcclusionStateNotification
        ] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    guard let self, self.settings.isEnabled else { return }
                    self.apply()
                }
            )
        }
        // Довершает включение Desktop Overlay, если оно было
        // отложено из-за того, что окно было в нативном fullscreen
        // (см. guard в apply()) — level/frame
        // нельзя было применить, пока переход не завершился.
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.isActivationPendingFullScreenExit else { return }
                self.isActivationPendingFullScreenExit = false
                guard self.settings.isEnabled else { return }
                self.apply()
            }
        )
    }

    /// Применяет/откатывает уровень, collectionBehavior, ignoresMouseEvents
    /// и фрейм окна для Desktop Overlay. Значение уровня подобрано эмпирически
    /// (публичной константы "чуть выше иконок, чуть ниже виджетов" у Apple
    /// нет) и может понадобиться донастроить.
    func apply() {
        guard let window else { return }
        let isEnabled = settings.isEnabled
        let isDesktopModeActive = settings.isDesktopModeActive

        // Нативный fullscreen — отдельная macOS Space, level/frame внутри
        // неё игнорируются композитором (а styleMask-правки — нет, отсюда
        // рассинхрон: кнопки/pill уже перестроились, а окно так и не легло
        // на уровень иконок стола). Сначала выходим из fullscreen и ждём
        // завершения перехода (didExitFullScreenNotification, см. attach),
        // и только потом применяем остальную конфигурацию.
        if isEnabled, window.styleMask.contains(.fullScreen) {
            isActivationPendingFullScreenExit = true
            window.toggleFullScreen(nil)
            return
        }

        if isEnabled {
            if savedWindowFrame == nil {
                savedWindowFrame = window.frame
            }
            // Уровень разный по режимам: Desktop mode — ниже иконок стола
            // (окно совсем не мешает), обычный режим — выше иконок, но ниже
            // окон приложений.
            let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
            window.level = NSWindow.Level(
                rawValue: isDesktopModeActive ? desktopIconLevel - 1 : desktopIconLevel + 1
            )
            window.collectionBehavior = [.ignoresCycle]
            // В обычном режиме "прозрачность" фона держится целиком на
            // VisualEffectBlur (живой блюр того, что позади окна) — само
            // NSWindow остаётся непрозрачным по умолчанию. В Desktop mode
            // блюр скрыт вместе с карточками (см. ContentView.body и ThoughtsApp.swift), и
            // без явного isOpaque/backgroundColor = .clear вместо настоящего
            // стола был виден сплошной непрозрачный фон окна.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            // WindowGroup в SwiftUI всегда рождает titled-окно
            // (hiddenTitleBar прячет только полосу, не сами traits) — без
            // явного снятия traits из styleMask курсор у верхнего края
            // показывает настоящие traffic-light кнопки на весь экран.
            // .titled — не только сами кнопки, но и причина зазора под
            // menu bar: у titled-окон AppKit сам поджимает frame ниже
            // строки меню, даже если явно попросить Y=0 через setFrame.
            window.styleMask.remove([.closable, .miniaturizable, .resizable, .titled])
            window.titleVisibility = .hidden
            window.title = ""
            // Окно закреплено: его нельзя сдвинуть ни за какую зону (раньше за верхнюю полосу можно было).
            window.isMovable = false
            window.isMovableByWindowBackground = false
            // Плавающий title pill позиционируется относительно верхнего
            // края фрейма окна (подтверждено эмпирически), поэтому подвинуть
            // его ниже без потери полного покрытия экрана сверху невозможно
            // — эти две вещи завязаны на один и тот же frame. Полное
            // покрытие приоритетнее (явно попросили не обрезать снова),
            // так что фрейм всегда во весь экран, начиная с Y=0.
            if let screen = window.screen ?? NSScreen.main {
                window.setFrame(screen.frame, display: true, animate: false)
            }
            registerHotKeys()
        } else {
            isActivationPendingFullScreenExit = false
            unregisterHotKeys()
            window.level = .normal
            window.collectionBehavior = []
            window.isMovable = true
            window.hasShadow = true
            window.styleMask.insert([.closable, .miniaturizable, .resizable, .titled])
            window.titleVisibility = .visible
            window.title = "Thoughts"
            if let savedWindowFrame {
                window.setFrame(savedWindowFrame, display: true, animate: false)
            }
            savedWindowFrame = nil
        }

        window.ignoresMouseEvents = isEnabled && isDesktopModeActive
    }

    /// ⌥D и запасной ⌃⌥D как глобальные хоткеи (см. GlobalHotKeyManager) —
    /// должны срабатывать, даже когда активное приложение не Thoughts, а
    /// Finder (ровно так и есть в Desktop mode после клика по иконке на
    /// столе). Цена: пока Overlay включён, ⌥D (∂) занят во всех приложениях.
    /// ⌃⌥1–9 (выход из Desktop mode) — глобальные всегда, см.
    /// AppDelegate.registerSpaceHotKeys.
    private func registerHotKeys() {
        // Вызывается и на каждую смену фокуса окна — регистрируем один раз.
        guard hotKeyTokens.isEmpty else { return }
        let settings = settings
        var tokens: [HotKeyToken] = []

        for modifiers in [optionKey, controlKey | optionKey] {
            if case .success(let token) = GlobalHotKeyManager.shared.register(keyCode: 2 /* kVK_ANSI_D */, modifiers: UInt32(modifiers), action: {
                // Иначе зажатое ⌥D (авто-повтор клавиши) непрерывно шлёт один
                // и тот же вход в Desktop mode заново.
                guard !settings.isDesktopModeActive else { return }
                settings.isDesktopModeActive = true
            }) {
                tokens.append(token)
            }
        }
        hotKeyTokens = tokens
    }

    private func unregisterHotKeys() {
        GlobalHotKeyManager.shared.unregister(hotKeyTokens)
        hotKeyTokens = []
    }
}
