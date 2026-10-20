import SwiftUI

/// Settings → Plugins: плагины (пока заготовка — менеджера ещё нет), шаблоны
/// карточек с переключателями и каталог.
struct PluginsSettingsTab: View {
    var plugins = PluginsModel.shared
    var templateSettings = TemplateSettings.shared

    private static let docsURL = URL(string: "https://github.com/alxxeu/thoughts-plugins/blob/main/docs/plugins.md")!

    var body: some View {
        Form {
            installedSection
            templatesSection
            catalogSection
        }
        .formStyle(.grouped)
        .onAppear { UserTemplateStore.shared.reload() }
    }

    // MARK: - Плагины

    private var installedSection: some View {
        Section {
            if plugins.installed.isEmpty {
                Text("No plugins installed")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(plugins.installed) { plugin in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plugin.name)
                        Text("\(plugin.version) \u{00B7} \(plugin.author) \u{00B7} \(plugin.itemCount) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            SettingsRowButton(title: "Install Plugin\u{2026}") {}
                .disabled(true)
                .foregroundStyle(.secondary)
            SettingsRowButton(title: "Open Plugins Folder") { plugins.openFolder() }
        } header: {
            Text("Plugins")
        } footer: {
            Text("Plugins add fonts, themes and templates, and never run code. Installing is coming soon.")
        }
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
