import Foundation
import Observation

/// Иконки капсулы Space, которые можно скрыть. Имя Space и шестерёнка настройки
/// скрыть нельзя.
enum ToolbarItem: String, CaseIterable, Identifiable {
    case askAI, tidyCards, clearSpace, plugins

    /// Пазл Plugins — только в сборке с флагом PLUGINS (плагины отложены).
    static var available: [ToolbarItem] {
        #if PLUGINS
        return allCases
        #else
        return allCases.filter { $0 != .plugins }
        #endif
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askAI: return "Ask AI"
        case .tidyCards: return "Tidy Cards"
        case .clearSpace: return "Clear Space"
        case .plugins: return "Plugins"
        }
    }

    var symbol: String {
        switch self {
        case .askAI: return "sparkle"
        case .tidyCards: return "square.grid.2x2.fill"
        case .clearSpace: return "trash.fill"
        case .plugins: return "puzzlepiece.extension.fill"
        }
    }
}

/// Какие иконки капсулы скрыты — общее для всех Spaces, хранится в UserDefaults.
@Observable
final class SpaceToolbarSettings {
    static let shared = SpaceToolbarSettings()
    private static let key = "spaceToolbar.hiddenItems"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var hidden: Set<ToolbarItem>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.key) ?? []
        hidden = Set(stored.compactMap(ToolbarItem.init(rawValue:)))
    }

    func isHidden(_ item: ToolbarItem) -> Bool { hidden.contains(item) }

    func setHidden(_ item: ToolbarItem, _ isHidden: Bool) {
        if isHidden { hidden.insert(item) } else { hidden.remove(item) }
        defaults.set(hidden.map(\.rawValue).sorted(), forKey: Self.key)
    }

    func reset() {
        hidden = []
        defaults.removeObject(forKey: Self.key)
    }
}
