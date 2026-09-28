import SwiftUI
import AppKit

// Кастомизация карточек и канвы — каждый вариант описан данными со
// строковым id, а не enum-кейсом: встроенные наборы ниже — это просто
// статические массивы, и будущие плагины (см. docs/plugins.md) смогут
// добавлять свои варианты в тот же реестр под id вида "pluginID/itemID".
// Неизвестный id (например, после удаления плагина) всегда откатывается
// к варианту по умолчанию, а не ломает отрисовку.

/// Итоговый стиль текста карточки — единственное, что редактор
/// (CardTextView) знает о кастомизации.
struct CardTypography: Equatable {
    let font: NSFont
    let color: NSColor

    static let baseFontSize: CGFloat = 15

    /// Цвет текста до появления кастомизации — им же заархивированы все
    /// старые formattingData, поэтому он всегда считается "базовым" (см.
    /// CardTextView.isBaseColor).
    static let legacyTextColor = NSColor.white.withAlphaComponent(0.88)
}

// MARK: - Шрифт

enum CardFontSource: Hashable {
    /// Системный шрифт в одном из дизайнов SF (default/rounded/serif/mono).
    case system(NSFontDescriptor.SystemDesign)
    /// Любое установленное семейство из NSFontManager.
    case family(String)
}

struct CardFontOption: Identifiable, Hashable {
    let id: String
    let title: String
    let source: CardFontSource

    func font(size: CGFloat = CardTypography.baseFontSize) -> NSFont {
        switch source {
        case .system(let design):
            let base = NSFont.systemFont(ofSize: size)
            guard let descriptor = base.fontDescriptor.withDesign(design),
                  let font = NSFont(descriptor: descriptor, size: size) else { return base }
            return font
        case .family(let name):
            return NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size)
                ?? NSFont.systemFont(ofSize: size)
        }
    }

    static let defaultID = "builtin.system"
    private static let familyPrefix = "family:"

    static let builtIn: [CardFontOption] = [
        CardFontOption(id: defaultID, title: "System", source: .system(.default)),
        CardFontOption(id: "builtin.rounded", title: "Rounded", source: .system(.rounded)),
        CardFontOption(id: "builtin.serif", title: "Serif", source: .system(.serif)),
        CardFontOption(id: "builtin.mono", title: "Mono", source: .system(.monospaced))
    ]

    static func family(_ name: String) -> CardFontOption {
        CardFontOption(id: familyPrefix + name, title: name, source: .family(name))
    }

    static var installedFamilies: [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func resolve(_ id: String) -> CardFontOption {
        if let option = builtIn.first(where: { $0.id == id }) {
            return option
        }
        if id.hasPrefix(familyPrefix) {
            let name = String(id.dropFirst(familyPrefix.count))
            if NSFontManager.shared.availableFontFamilies.contains(name) {
                return family(name)
            }
        }
        return builtIn[0]
    }
}

// MARK: - Цвет текста

struct TextColorOption: Identifiable, Hashable {
    let id: String
    let title: String
    let color: NSColor

    static let defaultID = "builtin.default"
    private static let customPrefix = "custom:"

    /// Только светлые тона — фон карточки тёмный в обеих темах (см.
    /// CardSurfaceStyle), тёмный текст на нём был бы нечитаем.
    static let builtIn: [TextColorOption] = [
        TextColorOption(id: defaultID, title: "Default", color: CardTypography.legacyTextColor),
        preset("builtin.warm", "Warm", 0xF3E3C3),
        preset("builtin.amber", "Amber", 0xF7D58A),
        preset("builtin.rose", "Rose", 0xF5C6D0),
        preset("builtin.lavender", "Lavender", 0xD6CCF5),
        preset("builtin.sky", "Sky", 0xBCD9F5),
        preset("builtin.mint", "Mint", 0xBFEBD6)
    ]

    private static func preset(_ id: String, _ title: String, _ rgb: Int) -> TextColorOption {
        TextColorOption(id: id, title: title, color: NSColor(rgb: rgb).withAlphaComponent(0.92))
    }

    static func custom(_ color: NSColor) -> TextColorOption {
        let hex = color.hexString
        return TextColorOption(id: customPrefix + hex, title: "Custom", color: NSColor(hex: hex) ?? color)
    }

    static func isCustom(_ id: String) -> Bool {
        id.hasPrefix(customPrefix)
    }

    static func resolve(_ id: String) -> TextColorOption {
        if let option = builtIn.first(where: { $0.id == id }) {
            return option
        }
        if id.hasPrefix(customPrefix), let color = NSColor(hex: String(id.dropFirst(customPrefix.count))) {
            return TextColorOption(id: id, title: "Custom", color: color)
        }
        return builtIn[0]
    }
}

// MARK: - Паттерн фона канвы

struct CanvasPattern: Identifiable, Hashable {
    enum Kind: Hashable {
        case none, dots, grid, lines, crosses, diagonal
    }

    let id: String
    let title: String
    let kind: Kind
    /// Шаг повтора паттерна в pt.
    var spacing: CGFloat = 24
    var lineWidth: CGFloat = 0.5
    var dotSize: CGFloat = 2

    static let defaultID = "builtin.none"

    static let builtIn: [CanvasPattern] = [
        CanvasPattern(id: defaultID, title: "None", kind: .none),
        CanvasPattern(id: "builtin.dots", title: "Dots", kind: .dots, spacing: 20, dotSize: 2),
        CanvasPattern(id: "builtin.grid", title: "Grid", kind: .grid, spacing: 30),
        CanvasPattern(id: "builtin.lines", title: "Lines", kind: .lines, spacing: 28),
        CanvasPattern(id: "builtin.crosses", title: "Crosses", kind: .crosses, spacing: 30, lineWidth: 1, dotSize: 6),
        CanvasPattern(id: "builtin.diagonal", title: "Diagonal", kind: .diagonal, spacing: 18)
    ]

    static func resolve(_ id: String) -> CanvasPattern {
        builtIn.first { $0.id == id } ?? builtIn[0]
    }
}

// MARK: - Hex-цвета

extension NSColor {
    convenience init(rgb: Int) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    /// "#RRGGBB" (решётка необязательна).
    convenience init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        self.init(rgb: value)
    }

    var hexString: String {
        let srgb = usingColorSpace(.sRGB) ?? self
        let r = Int((srgb.redComponent * 255).rounded())
        let g = Int((srgb.greenComponent * 255).rounded())
        let b = Int((srgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// isEqual у NSColor чувствителен к цветовому пространству —
    /// разархивированный цвет может прийти в другом, чем исходный.
    func isApproximatelyEqual(to other: NSColor) -> Bool {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return false }
        let epsilon: CGFloat = 0.004
        return abs(a.redComponent - b.redComponent) < epsilon
            && abs(a.greenComponent - b.greenComponent) < epsilon
            && abs(a.blueComponent - b.blueComponent) < epsilon
            && abs(a.alphaComponent - b.alphaComponent) < epsilon
    }
}
