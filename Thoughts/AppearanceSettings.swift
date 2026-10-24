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
    private static let textSizeKey = "appearance.textSize"
    private static let canvasPatternKey = "appearance.canvasPattern"
    private static let patternOpacityKey = "appearance.patternOpacity"
    private static let backgroundKey = "appearance.background"
    private static let recentTextColorsKey = "appearance.recentTextColors"
    private static let recentBackgroundColorsKey = "appearance.recentFullScreenBackgrounds"

    /// Сколько последних своих цветов помнить у каждого пикера.
    static let recentColorsLimit = 3

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

    var textSize: CardTextSize {
        didSet {
            UserDefaults.standard.set(textSize.rawValue, forKey: Self.textSizeKey)
            updateTypography()
        }
    }

    var textColorID: String {
        didSet {
            UserDefaults.standard.set(textColorID, forKey: Self.textColorKey)
            updateTypography()
        }
    }

    /// Последние свои цвета текста (id вида `custom:#RRGGBB`), новые первыми.
    private(set) var recentTextColorIDs: [String]
    /// Последние свои цвета фона.
    private(set) var recentBackgroundIDs: [String]

    @ObservationIgnored private var lastTextColorPick = Date.distantPast
    @ObservationIgnored private var lastBackgroundPick = Date.distantPast

    var canvasPatternID: String {
        didSet {
            UserDefaults.standard.set(canvasPatternID, forKey: Self.canvasPatternKey)
        }
    }

    /// Фон окна во всех режимах (окно, fullscreen, Desktop Overlay): Material / цвет / свои обои.
    var backgroundID: String {
        didSet {
            UserDefaults.standard.set(backgroundID, forKey: Self.backgroundKey)
        }
    }

    var background: BackgroundChoice { BackgroundChoice.resolve(backgroundID) }

    /// Растёт при смене картинки обоев, чтобы фон перерисовался.
    private(set) var backgroundImageRevision = 0

    /// Диалог выбора картинки; выбрали — она становится фоном.
    func chooseBackgroundImage(startingIn directory: URL? = nil, message: String) {
        guard BackgroundImagePicker.pick(startingIn: directory, message: message) else { return }
        backgroundImageRevision += 1
        backgroundID = BackgroundChoice.imageID
    }

    var patternOpacity: Double {
        didSet {
            UserDefaults.standard.set(patternOpacity, forKey: Self.patternOpacityKey)
        }
    }

    /// Хранится, а не вычисляется на лету: CardView читает его на каждый
    /// body, а resolve семейства шрифта пробегает весь список установленных.
    private(set) var cardTypography: CardTypography

    /// Цвет из ColorPicker: применить и запомнить среди недавних. Клик по
    /// уже сохранённому свотчу идёт мимо — свотчи не прыгают под курсором.
    func pickCustomTextColor(_ color: NSColor) {
        textColorID = TextColorOption.custom(color).id
        Self.remember(textColorID, in: &recentTextColorIDs, stamp: &lastTextColorPick, key: Self.recentTextColorsKey)
    }

    func pickCustomBackground(_ color: NSColor) {
        backgroundID = FullScreenBackgroundOption.custom(color).id
        Self.remember(backgroundID, in: &recentBackgroundIDs, stamp: &lastBackgroundPick, key: Self.recentBackgroundColorsKey)
    }

    /// Свой цвет — в начало списка недавних (без повторов, не больше трёх).
    /// ColorPicker шлёт значение на каждое движение по палитре: выборы чаще
    /// раза в 1.5 с считаем одним и заменяем первый элемент, а не копим
    /// промежуточные оттенки.
    private static func remember(_ id: String, in list: inout [String], stamp: inout Date, key: String) {
        let now = Date()
        if now.timeIntervalSince(stamp) < 1.5, !list.isEmpty {
            list.removeFirst()
        }
        stamp = now
        list.removeAll { $0 == id }
        list.insert(id, at: 0)
        if list.count > recentColorsLimit { list.removeLast(list.count - recentColorsLimit) }
        UserDefaults.standard.set(list, forKey: key)
    }

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
        let size = defaults.string(forKey: Self.textSizeKey).flatMap(CardTextSize.init(rawValue:)) ?? .defaultValue
        cardFontID = fontID
        textColorID = colorID
        textSize = size
        canvasPatternID = defaults.string(forKey: Self.canvasPatternKey) ?? CanvasPattern.defaultID
        backgroundID = defaults.string(forKey: Self.backgroundKey) ?? BackgroundChoice.materialID
        recentTextColorIDs = defaults.stringArray(forKey: Self.recentTextColorsKey) ?? []
        recentBackgroundIDs = defaults.stringArray(forKey: Self.recentBackgroundColorsKey) ?? []
        if defaults.object(forKey: Self.patternOpacityKey) != nil {
            patternOpacity = defaults.double(forKey: Self.patternOpacityKey)
        } else {
            patternOpacity = 0.12
        }
        cardTypography = Self.makeTypography(fontID: fontID, colorID: colorID, size: size)
    }

    /// Плагин со шрифтом или цветом включили/выключили — id те же, а итог другой.
    func refreshTypography() { updateTypography() }

    /// Тема из плагина: применяет то, что в ней задано, остальное не трогает.
    func apply(_ theme: ThemeOption) {
        if let id = theme.fontID { cardFontID = id }
        if let id = theme.textColorID { textColorID = id }
        if let id = theme.patternID { canvasPatternID = id }
        if let value = theme.patternIntensity { patternOpacity = value }
    }

    private func updateTypography() {
        let typography = Self.makeTypography(fontID: cardFontID, colorID: textColorID, size: textSize)
        if typography != cardTypography {
            cardTypography = typography
        }
    }

    private static func makeTypography(fontID: String, colorID: String, size: CardTextSize) -> CardTypography {
        CardTypography(
            font: CardFontOption.resolve(fontID).font(size: size.pointSize),
            color: TextColorOption.resolve(colorID).color
        )
    }
}
