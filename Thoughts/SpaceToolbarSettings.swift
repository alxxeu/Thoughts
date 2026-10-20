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

/// Какие иконки капсулы скрыты и в каком они порядке — общее для всех Spaces,
/// хранится в UserDefaults.
@Observable
final class SpaceToolbarSettings {
    static let shared = SpaceToolbarSettings()
    private static let key = "spaceToolbar.hiddenItems"
    private static let orderKey = "spaceToolbar.order"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var hidden: Set<ToolbarItem>
    /// Порядок иконок (перетаскиванием в режиме правки).
    private(set) var order: [ToolbarItem]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.key) ?? []
        hidden = Set(stored.compactMap(ToolbarItem.init(rawValue:)))
        order = Self.completeOrder(defaults.stringArray(forKey: Self.orderKey) ?? [])
    }

    /// Сохранённый порядок без неизвестных; новые иконки — в конце, как в allCases.
    private static func completeOrder(_ stored: [String]) -> [ToolbarItem] {
        var result: [ToolbarItem] = []
        for item in stored.compactMap(ToolbarItem.init(rawValue:)) where !result.contains(item) {
            result.append(item)
        }
        return result + ToolbarItem.allCases.filter { !result.contains($0) }
    }

    /// Поставить иконку на место `index` в видимом ряду `row` (перетаскивание).
    /// Иконки вне ряда (Plugins без флага, Ask AI при выключенном AI) — в конце.
    func move(_ item: ToolbarItem, to index: Int, within row: [ToolbarItem]) {
        guard let from = row.firstIndex(of: item) else { return }
        var newRow = row
        newRow.remove(at: from)
        newRow.insert(item, at: min(max(index, 0), newRow.count))
        order = newRow + order.filter { !newRow.contains($0) }
        defaults.set(order.map(\.rawValue), forKey: Self.orderKey)
    }

    func isHidden(_ item: ToolbarItem) -> Bool { hidden.contains(item) }

    func setHidden(_ item: ToolbarItem, _ isHidden: Bool) {
        if isHidden { hidden.insert(item) } else { hidden.remove(item) }
        defaults.set(hidden.map(\.rawValue).sorted(), forKey: Self.key)
    }

    func reset() {
        hidden = []
        order = ToolbarItem.allCases
        defaults.removeObject(forKey: Self.key)
        defaults.removeObject(forKey: Self.orderKey)
    }
}
