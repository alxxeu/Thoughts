import AppKit
import Observation

/// Установленный плагин (описание для списка в Settings и на панели пазла).
struct PluginInfo: Identifiable, Equatable {
    let id: String
    var name: String
    var version: String
    var author: String
    /// Сколько элементов добавляет плагин (шрифты, темы, шаблоны…).
    var itemCount: Int
    var isEnabled: Bool
}

/// Заготовка под менеджер плагинов (см. docs/plugins.md, BACKLOG «Шаблоны, плагины
/// и каталог»): список пока всегда пуст, будущий PluginManager его заполнит. Уже
/// отдаёт папку `Plugins/` (в Debug — своя, как у доски).
@Observable
final class PluginsModel {
    static let shared = PluginsModel()

    private(set) var installed: [PluginInfo] = []

    var folderURL: URL { BoardStore.dataFolder.appendingPathComponent("Plugins", isDirectory: true) }

    /// Создаёт папку (если её нет) и показывает в Finder.
    func openFolder() {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folderURL)
    }
}
