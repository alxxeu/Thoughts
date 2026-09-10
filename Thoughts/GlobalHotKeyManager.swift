import Carbon.HIToolbox
import AppKit

/// Глобальные хоткеты для Desktop Overlay (⌥D, ⌥1–9) — должны срабатывать
/// независимо от того, какое приложение сейчас активно: клик по иконке на
/// столе в Desktop mode делает активным Finder, а не Thoughts, и обычные
/// SwiftUI .keyboardShortcut/CommandMenu (шorткаты уровня меню приложения)
/// в этот момент вообще не получают событие — оно достаётся Finder.
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

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    private static let signature: OSType = 0x54484F55 // "THOU"

    private init() {}

    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        if eventHandler == nil {
            installEventHandler()
        }

        let id = nextID
        nextID += 1
        handlers[id] = action

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRefs.append(ref)
        }
    }

    func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        handlers.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil
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
