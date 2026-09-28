import AppKit
import Carbon.HIToolbox

/// Сочетание для глобального хоткея: физический keyCode (не символ — не
/// зависит от раскладки, как и остальные хоткеи приложения) + Carbon-маска
/// модификаторов. keyName — только для отображения, снимается в момент
/// записи с ASCII-раскладки (см. HotKeyShortcut.keyName(for:)).
struct HotKeyShortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyName: String

    /// ⌃⌥⌘N, а не ⌃⌥N: ⌃⌥N — популярный дефолт у других приложений
    /// быстрых заметок (QuickNote и т.п.), а конфликт между процессами
    /// Carbon не сообщает — RegisterEventHotKey успешен, но нажатие забирает
    /// чужой хоткей. ⌃⌥Space тоже не годится — это системное переключение
    /// источника ввода.
    static let quickCaptureDefault = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_N),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        keyName: "N"
    )

    /// Порядок символов — как в системных меню macOS: ⌃⌥⇧⌘.
    var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "\u{2303}" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "\u{2325}" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "\u{21E7}" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "\u{2318}" }
        return result + keyName
    }

    /// Глобальный хоткей без ⌘/⌃/⌥ перехватывал бы обычный набор текста во
    /// всех приложениях — такие сочетания не принимаем.
    static func from(event: NSEvent) -> HotKeyShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else { return nil }

        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }

        return HotKeyShortcut(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: modifiers,
            keyName: keyName(for: event.keyCode)
        )
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "\u{21A9}", kVK_Tab: "\u{21E5}",
        kVK_Delete: "\u{232B}", kVK_ForwardDelete: "\u{2326}", kVK_Escape: "\u{238B}",
        kVK_LeftArrow: "\u{2190}", kVK_RightArrow: "\u{2192}",
        kVK_UpArrow: "\u{2191}", kVK_DownArrow: "\u{2193}",
        kVK_Home: "\u{2196}", kVK_End: "\u{2198}",
        kVK_PageUp: "\u{21DE}", kVK_PageDown: "\u{21DF}",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12"
    ]

    /// Имя клавиши по ASCII-раскладке — на русской раскладке та же
    /// физическая клавиша показывается как "N", а не "Т".
    static func keyName(for keyCode: UInt16) -> String {
        if let special = specialKeyNames[Int(keyCode)] {
            return special
        }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "#\(keyCode)"
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return "#\(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// Quick Capture — глобальный хоткей, открывающий плавающую панель для
/// быстрой записи карточки (см. QuickCapturePanel.swift). Persist через
/// UserDefaults, тот же стиль ключей, что в DesktopOverlaySettings.
/// Регистрацией самого хоткея управляет QuickCaptureController — здесь
/// только хранимые значения.
@Observable
final class QuickCaptureSettings {
    static let shared = QuickCaptureSettings()

    private static let isEnabledKey = "quickCapture.isEnabled"
    private static let shortcutKey = "quickCapture.shortcut"

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.isEnabledKey)
        }
    }

    var shortcut: HotKeyShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: Self.shortcutKey)
            }
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Self.isEnabledKey) == nil ? true : defaults.bool(forKey: Self.isEnabledKey)
        if let data = defaults.data(forKey: Self.shortcutKey),
           let stored = try? JSONDecoder().decode(HotKeyShortcut.self, from: data) {
            shortcut = stored
        } else {
            shortcut = .quickCaptureDefault
        }
    }
}
