import Foundation

/// Какие шаблоны включены (Settings → Plugins → Templates). Включённые идут
/// прямым списком в правом клике по пустому месту доски, сразу после
/// «New Card». Храним выключенные — новые шаблоны (из плагинов, каталога)
/// появляются включёнными.
@Observable
final class TemplateSettings {
    static let shared = TemplateSettings()

    private static let disabledKey = "templates.disabled"

    private var disabledIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(disabledIDs), forKey: Self.disabledKey) }
    }

    private init() {
        disabledIDs = Set(UserDefaults.standard.stringArray(forKey: Self.disabledKey) ?? [])
    }

    /// Все доступные: встроенные доски и файлы из папки шаблонов.
    var available: [CardTemplate] {
        CardTemplate.all + UserTemplateStore.shared.templates.map(CardTemplate.init)
    }

    var enabled: [CardTemplate] {
        available.filter { isEnabled($0.id) }
    }

    func isEnabled(_ id: String) -> Bool { !disabledIDs.contains(id) }

    func setEnabled(_ enabled: Bool, for id: String) {
        if enabled { disabledIDs.remove(id) } else { disabledIDs.insert(id) }
    }
}
