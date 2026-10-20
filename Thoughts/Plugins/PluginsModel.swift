import AppKit
import CoreText
import Observation

/// Пакет в папке `Plugins/`: исправный (manifest) или битый (error — показывается
/// в списке Settings, а не роняет скан).
struct InstalledPlugin: Identifiable, Equatable {
    let id: String
    let url: URL
    let manifest: PluginManifest?
    let error: String?
    var isEnabled: Bool

    var name: String { manifest?.name ?? url.deletingPathExtension().lastPathComponent }
    var version: String { manifest?.version ?? "" }
    var author: String { manifest?.author ?? "" }
    var itemCount: Int { manifest?.itemCount ?? 0 }
}

/// Что добавляют включённые плагины — реестры Customization и шаблоны читают
/// это вместе со встроенными вариантами. Id элементов — `pluginID/itemID`.
struct PluginContributions {
    var fonts: [CardFontOption] = []
    var textColors: [TextColorOption] = []
    var patterns: [CanvasPattern] = []
    var themes: [ThemeOption] = []
    var templates: [TemplateGroup] = []
}

/// Менеджер плагинов (Phase 1, thoughts-plugins/docs/plugins.md): сканирует
/// `Plugins/` (в Debug — своя папка, как у доски), проверяет пакеты, ставит,
/// удаляет, включает/выключает и регистрирует шрифты только для этого процесса.
@Observable
final class PluginsModel {
    static let shared = PluginsModel()

    private static let disabledKey = "plugins.disabled"

    private(set) var installed: [InstalledPlugin] = []
    private(set) var contributions = PluginContributions()

    private var disabledIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(disabledIDs), forKey: Self.disabledKey) }
    }
    @ObservationIgnored private var registeredFonts: Set<URL> = []
    private let folder: URL

    init(folder: URL? = nil) {
        self.folder = folder ?? BoardStore.dataFolder.appendingPathComponent("Plugins", isDirectory: true)
        disabledIDs = Set(UserDefaults.standard.stringArray(forKey: Self.disabledKey) ?? [])
    }

    var folderURL: URL { folder }

    // MARK: - Скан

    /// Перечитать папку: при запуске, при открытии Settings → Plugins и кнопкой Reload.
    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        var plugins: [InstalledPlugin] = []
        for url in urls where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            do {
                let manifest = try PluginValidator.validate(packageAt: url)
                // Два пакета с одним id (например, скопировали руками) — второй битый.
                if plugins.contains(where: { $0.id == manifest.id }) {
                    plugins.append(InstalledPlugin(id: url.lastPathComponent, url: url, manifest: nil,
                                                   error: "Another installed plugin already uses the id \u{201C}\(manifest.id)\u{201D}.", isEnabled: false))
                    continue
                }
                plugins.append(InstalledPlugin(id: manifest.id, url: url, manifest: manifest, error: nil,
                                               isEnabled: !disabledIDs.contains(manifest.id)))
            } catch {
                plugins.append(InstalledPlugin(id: url.lastPathComponent, url: url, manifest: nil,
                                               error: error.localizedDescription, isEnabled: false))
            }
        }
        installed = plugins.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        rebuildContributions()
    }

    func setEnabled(_ enabled: Bool, for plugin: InstalledPlugin) {
        guard plugin.manifest != nil else { return }
        if enabled { disabledIDs.remove(plugin.id) } else { disabledIDs.insert(plugin.id) }
        if let index = installed.firstIndex(where: { $0.id == plugin.id }) {
            installed[index].isEnabled = enabled
        }
        rebuildContributions()
    }

    // MARK: - Установка и удаление

    /// Проверка и копия в `Plugins/<id>/`. Тот же id — обновление только более
    /// новой версией. Пакет никогда не работает с исходного места.
    @discardableResult
    func install(from source: URL) throws -> InstalledPlugin {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let manifest = try PluginValidator.validate(packageAt: source)
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        if let existing = installed.first(where: { $0.id == manifest.id }), let old = existing.manifest,
           PluginValidator.compareVersions(manifest.version, old.version) != .orderedDescending {
            throw PluginError.alreadyInstalled(old.version)
        }

        let destination = folder.appendingPathComponent(manifest.id, isDirectory: true)
        let staging = folder.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        try fm.copyItem(at: source, to: staging)
        // Старую версию (в т.ч. под другим именем папки) убираем только после
        // удачного копирования новой.
        for old in installed where old.id == manifest.id && old.url != destination {
            try? fm.removeItem(at: old.url)
        }
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: destination)
        }

        reload()
        return installed.first { $0.id == manifest.id }
            ?? InstalledPlugin(id: manifest.id, url: destination, manifest: manifest, error: nil, isEnabled: true)
    }

    func remove(_ plugin: InstalledPlugin) {
        try? FileManager.default.removeItem(at: plugin.url)
        disabledIDs.remove(plugin.id)
        reload()
    }

    func reveal(_ plugin: InstalledPlugin) {
        NSWorkspace.shared.activateFileViewerSelecting([plugin.url])
    }

    /// Создаёт папку (если её нет) и показывает в Finder.
    func openFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    // MARK: - Вклад включённых плагинов

    private func rebuildContributions() {
        var result = PluginContributions()
        var neededFonts: Set<URL> = []

        for plugin in installed where plugin.isEnabled {
            guard let manifest = plugin.manifest, let c = manifest.contributes else { continue }
            let prefix = manifest.id + "/"

            for font in c.fonts ?? [] {
                guard let file = try? PluginValidator.fileInside(plugin.url, font.file, what: font.id) else { continue }
                neededFonts.insert(file)
                result.fonts.append(CardFontOption(id: prefix + font.id, title: font.name, source: .family(font.family)))
            }
            for color in c.textColors ?? [] {
                guard let value = NSColor(hex: color.hex) else { continue }
                result.textColors.append(TextColorOption(id: prefix + color.id, title: color.name, color: value))
            }
            for pattern in c.patterns ?? [] {
                guard let kind = PluginValidator.patternKinds[pattern.kind] else { continue }
                var item = CanvasPattern(id: prefix + pattern.id, title: pattern.name, kind: kind)
                if let v = pattern.spacing { item.spacing = CGFloat(v) }
                if let v = pattern.lineWidth { item.lineWidth = CGFloat(v) }
                if let v = pattern.dotSize { item.dotSize = CGFloat(v) }
                result.patterns.append(item)
            }
            for theme in c.themes ?? [] {
                result.themes.append(ThemeOption(id: prefix + theme.id, title: theme.name, fontID: theme.font,
                                                 textColorID: theme.textColor, patternID: theme.pattern,
                                                 patternIntensity: theme.patternIntensity))
            }
            for template in c.cardTemplates ?? [] {
                result.templates.append(Self.group(for: template, prefix: prefix))
            }
        }

        registerFonts(neededFonts)
        contributions = result
        // Шрифт или цвет из плагина мог стать (не)доступен — пересобрать стиль текста.
        AppearanceSettings.shared.refreshTypography()
    }

    private static func group(for template: PluginManifest.Template, prefix: String) -> TemplateGroup {
        let id = prefix + template.id
        if let variants = template.variants {
            let cards = variants.enumerated().map { index, v in
                CardTemplate(id: "\(id)/\(index)", name: v.name, note: v.note ?? "", text: v.text,
                             columns: v.size.columns, rows: v.size.rows, tag: v.tag.flatMap(CardTagColor.init(rawValue:)))
            }
            return TemplateGroup(id: id, name: template.name, menuTitle: template.menuTitle ?? template.name, variants: cards)
        }
        let card = CardTemplate(id: id, name: template.name, note: template.note ?? "", text: template.text ?? "",
                                columns: template.size?.columns ?? 4, rows: template.size?.rows ?? 3,
                                tag: template.tag.flatMap(CardTagColor.init(rawValue:)))
        return TemplateGroup(card)
    }

    /// Шрифты — только для этого процесса (`.process`): в других приложениях их не
    /// видно, разрешений не нужно. Выключили/удалили плагин — регистрация снимается.
    private func registerFonts(_ needed: Set<URL>) {
        for url in registeredFonts.subtracting(needed) {
            CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        }
        for url in needed.subtracting(registeredFonts) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        registeredFonts = needed
    }
}
