import SwiftUI

/// Settings → Plugins: установленные плагины (установка, вкл/выкл, удаление), шаблоны
/// карточек с переключателями и каталог.
struct PluginsSettingsTab: View {
    var plugins = PluginsModel.shared
    var templateSettings = TemplateSettings.shared
    var converters = ConverterService.shared

    @State private var errorMessage: String?
    @State private var isDropTargeted = false
    @State private var pluginToRemove: InstalledPlugin?

    private static let docsURL = URL(string: "https://github.com/alxxeu/thoughts-plugins/blob/main/CREATE.md")!

    var body: some View {
        Form {
            convertersSection
            installedSection
            templatesSection
            catalogSection
        }
        .formStyle(.grouped)
        .onAppear {
            plugins.reload()
            UserTemplateStore.shared.reload()
        }
        .alert("Couldn\u{2019}t install the plugin", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Конвертеры

    private var convertersSection: some View {
        Section {
            Toggle("Converters", isOn: Binding(
                get: { converters.isEnabled },
                set: { converters.isEnabled = $0 }
            ))
            .toggleStyle(.switch)
        } footer: {
            Text("Type 12*3 or 5 ft in cm on its own line in a card: the result appears in gray, press Tab to insert it. Converters come from plugins.")
        }
    }

    // MARK: - Плагины

    private var installedSection: some View {
        Section {
            if plugins.installed.isEmpty {
                Text("No plugins installed")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(plugins.installed) { plugin in
                    pluginRow(plugin)
                }
            }
            SettingsRowButton(title: "Install Plugin\u{2026}") { installPlugins() }
            SettingsRowButton(title: "Open Plugins Folder") { plugins.openFolder() }
            SettingsRowButton(title: "Reload Plugins") { plugins.reload() }
        } header: {
            Text("Plugins")
        } footer: {
            Text("Plugins add converters, card templates, fonts and colors. Scripts run isolated: no access to your cards or files, and the internet only for the sites a plugin lists. Drop a .thoughtsplugin folder here to install it.")
        }
        .dropDestination(for: URL.self) { urls, _ in
            install(urls.filter { $0.pathExtension == PluginManifest.packageExtension })
            return true
        } isTargeted: { isDropTargeted = $0 }
        .opacity(isDropTargeted ? 0.6 : 1)
        .confirmationDialog(
            "Remove \u{201C}\(pluginToRemove?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { pluginToRemove != nil }, set: { if !$0 { pluginToRemove = nil } })
        ) {
            Button("Remove", role: .destructive) {
                if let plugin = pluginToRemove { plugins.remove(plugin) }
                pluginToRemove = nil
            }
        } message: {
            Text("Its fonts, colors, patterns, themes and templates disappear. Settings that used them go back to the defaults.")
        }
    }

    private func pluginRow(_ plugin: InstalledPlugin) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                if let error = plugin.error ?? plugins.runtimeErrors[plugin.id] {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(pluginSubtitle(plugin))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                plugins.reveal(plugin)
            } label: { Image(systemName: "magnifyingglass") }
                .help("Reveal in Finder")
            Button(role: .destructive) {
                pluginToRemove = plugin
            } label: { Image(systemName: "trash") }
                .help("Remove")
            if plugin.error == nil {
                Toggle("Enabled", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { plugins.setEnabled($0, for: plugin) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
        .buttonStyle(.borderless)
    }

    private func pluginSubtitle(_ plugin: InstalledPlugin) -> String {
        let items = plugin.itemCount == 1 ? "1 item" : "\(plugin.itemCount) items"
        var parts = [plugin.version, plugin.author, items]
        if let hosts = plugin.manifest?.networkHosts, !hosts.isEmpty {
            parts.append("connects to " + hosts.joined(separator: ", "))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    /// Плагин со скриптом — сказать, что он запускает код и куда ходит в сеть.
    private func confirmScript(_ manifest: PluginManifest) -> Bool {
        guard manifest.main != nil else { return true }
        let alert = NSAlert()
        alert.messageText = "Install \u{201C}\(manifest.name)\u{201D}?"
        let hosts = manifest.networkHosts
        alert.informativeText = hosts.isEmpty
            ? "This plugin runs a script. It can\u{2019}t read your cards or connect to the internet."
            : "This plugin runs a script. It can\u{2019}t read your cards, but it can connect to: \(hosts.joined(separator: ", ")). What you type on a converter line may be sent there."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Пакет — папка `.thoughtsplugin`: свой тип файла пока не зарегистрирован,
    /// поэтому выбираем папки и проверяем расширение сами.
    private func installPlugins() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Install"
        panel.message = "Choose a .thoughtsplugin folder"
        guard panel.runModal() == .OK else { return }
        install(panel.urls)
    }

    private func install(_ urls: [URL]) {
        var errors: [String] = []
        for url in urls {
            guard url.pathExtension == PluginManifest.packageExtension else {
                errors.append("\(url.lastPathComponent): \(PluginError.notAPackage.localizedDescription)")
                continue
            }
            do {
                guard confirmScript(try plugins.inspect(url)) else { continue }
                try plugins.install(from: url)
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !errors.isEmpty { errorMessage = errors.joined(separator: "\n\n") }
    }

    // MARK: - Шаблоны

    /// Все доступные шаблоны с переключателями: включённые идут прямым списком в
    /// правом клике по доске после «New Card». Сейчас это встроенные доски;
    /// потом добавятся шаблоны из плагинов и каталога.
    private var templatesSection: some View {
        Section {
            ForEach(templateSettings.available) { group in
                Toggle(isOn: Binding(
                    get: { templateSettings.isEnabled(group.id) },
                    set: { templateSettings.setEnabled($0, for: group.id) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                        Text(subtitle(for: group))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        } header: {
            Text("Templates")
        } footer: {
            Text("Turned-on templates appear when you right-click an empty spot on the board, after New Card.")
        }
    }

    /// Варианты через запятую («1 Column, 2 Columns…»); у одиночного —
    /// комментарий и размер в клетках.
    private func subtitle(for group: TemplateGroup) -> String {
        if group.variants.count > 1 {
            return group.variants.map(\.name).joined(separator: ", ")
        }
        guard let template = group.variants.first else { return "" }
        let size = "\(template.columns)\u{00D7}\(template.rows)"
        return template.note.isEmpty ? size : "\(template.note) \u{00B7} \(size)"
    }

    // MARK: - Каталог

    private var catalogSection: some View {
        Section {
            SettingsRowButton(title: "Browse Catalog\u{2026}") {}
                .disabled(true)
                .foregroundStyle(.secondary)
            Link(destination: Self.docsURL) {
                HStack {
                    Text("Build Your Own")
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Catalog")
        } footer: {
            Text("A community catalog of plugins and templates is planned.")
        }
    }
}
