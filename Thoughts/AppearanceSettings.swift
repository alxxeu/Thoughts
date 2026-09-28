import AppKit

enum AppColorScheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Пользовательский выбор темы (независимо от системной Light/Dark) —
/// применяется через .preferredColorScheme в ThoughtsApp — и кастомизация
/// карточек/канвы (см. Customization.swift). Persist через UserDefaults,
/// тот же стиль ключей, что в SecuritySettings.
@Observable
final class AppearanceSettings {
    static let shared = AppearanceSettings()

    private static let colorSchemeKey = "appearance.colorScheme"
    private static let cardFontKey = "appearance.cardFont"
    private static let textColorKey = "appearance.textColor"
    private static let canvasPatternKey = "appearance.canvasPattern"
    private static let patternOpacityKey = "appearance.patternOpacity"

    static let patternOpacityRange: ClosedRange<Double> = 0.04...0.3

    var colorScheme: AppColorScheme {
        didSet {
            UserDefaults.standard.set(colorScheme.rawValue, forKey: Self.colorSchemeKey)
        }
    }

    var cardFontID: String {
        didSet {
            UserDefaults.standard.set(cardFontID, forKey: Self.cardFontKey)
            updateTypography()
        }
    }

    var textColorID: String {
        didSet {
            UserDefaults.standard.set(textColorID, forKey: Self.textColorKey)
            updateTypography()
        }
    }

    var canvasPatternID: String {
        didSet {
            UserDefaults.standard.set(canvasPatternID, forKey: Self.canvasPatternKey)
        }
    }

    var patternOpacity: Double {
        didSet {
            UserDefaults.standard.set(patternOpacity, forKey: Self.patternOpacityKey)
        }
    }

    /// Хранится, а не вычисляется на лету: CardView читает его на каждый
    /// body, а resolve семейства шрифта пробегает весь список установленных.
    private(set) var cardTypography: CardTypography

    var canvasPattern: CanvasPattern {
        CanvasPattern.resolve(canvasPatternID)
    }

    private init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.colorSchemeKey),
           let value = AppColorScheme(rawValue: raw) {
            colorScheme = value
        } else {
            colorScheme = .system
        }
        let fontID = defaults.string(forKey: Self.cardFontKey) ?? CardFontOption.defaultID
        let colorID = defaults.string(forKey: Self.textColorKey) ?? TextColorOption.defaultID
        cardFontID = fontID
        textColorID = colorID
        canvasPatternID = defaults.string(forKey: Self.canvasPatternKey) ?? CanvasPattern.defaultID
        if defaults.object(forKey: Self.patternOpacityKey) != nil {
            patternOpacity = defaults.double(forKey: Self.patternOpacityKey)
        } else {
            patternOpacity = 0.12
        }
        cardTypography = Self.makeTypography(fontID: fontID, colorID: colorID)
    }

    private func updateTypography() {
        let typography = Self.makeTypography(fontID: cardFontID, colorID: textColorID)
        if typography != cardTypography {
            cardTypography = typography
        }
    }

    private static func makeTypography(fontID: String, colorID: String) -> CardTypography {
        CardTypography(
            font: CardFontOption.resolve(fontID).font(),
            color: TextColorOption.resolve(colorID).color
        )
    }
}
