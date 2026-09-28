import Carbon.HIToolbox
import AppKit

/// Идентификатор зарегистрированного хоткея — по нему владелец снимает
/// только свои хоткеи (см. unregister), не трогая чужие.
typealias HotKeyToken = UInt32

/// Глобальные хоткеты — должны срабатывать независимо от того, какое
/// приложение сейчас активно. Сейчас у них два независимых владельца:
/// Desktop Overlay (⌥D, ⌥1–9: клик по иконке на столе в Desktop mode делает
/// активным Finder, а не Thoughts, и обычные SwiftUI .keyboardShortcut/
/// CommandMenu в этот момент вообще не получают событие — оно достаётся
/// Finder) и Quick Capture (см. QuickCapturePanel.swift). Поэтому каждый
/// владелец снимает только свои токены — выключение Desktop Overlay не
/// должно заодно отключать Quick Capture.
///
/// Carbon RegisterEventHotKey, а не NSEvent.addGlobalMonitorForEvents:
/// последний тоже сработал бы независимо от фокуса, но требует разрешение
/// Input Monitoring (новый системный промпт, которого у приложения сейчас
/// нет вообще) и может только НАБЛЮДАТЬ событие, не потребляя его — клавиша
/// всё равно "утекла" бы в Finder. RegisterEventHotKey — тот же класс API,
/// которым десятилетиями пользуются menu-bar-утилиты для глобальных
/// шorткатов, разрешений не требует.
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    enum RegistrationError: Error {
        /// Комбинацию уже занял другой процесс (или этот же).
        case alreadyInUse
        case failed(OSStatus)
    }

    private var hotKeyRefs: [HotKeyToken: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var handlers: [HotKeyToken: () -> Void] = [:]
    private var nextID: HotKeyToken = 1

    private static let signature: OSType = 0x54484F55 // "THOU"

    private init() {}

    /// Виртуальные keyCode — физические позиции клавиш на ANSI-клавиатуре,
    /// не зависят от активной раскладки; modifiers — Carbon-маска
    /// (optionKey, controlKey и т.п.).
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Result<HotKeyToken, RegistrationError> {
        if eventHandler == nil {
            installEventHandler()
        }

        let id = nextID
        nextID += 1

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            removeEventHandlerIfUnused()
            return .failure(status == OSStatus(eventHotKeyExistsErr) ? .alreadyInUse : .failed(status))
        }

        hotKeyRefs[id] = ref
        handlers[id] = action
        return .success(id)
    }

    func unregister(_ tokens: [HotKeyToken]) {
        for token in tokens {
            if let ref = hotKeyRefs.removeValue(forKey: token) {
                UnregisterEventHotKey(ref)
            }
            handlers.removeValue(forKey: token)
        }
        removeEventHandlerIfUnused()
    }

    private func removeEventHandlerIfUnused() {
        guard hotKeyRefs.isEmpty, let eventHandler else { return }
        RemoveEventHandler(eventHandler)
        self.eventHandler = nil
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handlers[hotKeyID.id]?()
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
    }
}
