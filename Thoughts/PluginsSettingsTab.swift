import SwiftUI

/// Settings → Plugins: плагины (пока заготовка — менеджера ещё нет), шаблоны
/// карточек с переключателями и каталог.
struct PluginsSettingsTab: View {
    var plugins = PluginsModel.shared
    var templateSettings = TemplateSettings.shared

    private static let docsURL = URL(string: "https://github.com/alxxeu/Thoughts/blob/develop/docs/plugins.md")!

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
            ForEach(templateSettings.available) { template in
                Toggle(isOn: Binding(
                    get: { templateSettings.isEnabled(template.id) },
                    set: { templateSettings.setEnabled($0, for: template.id) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                        Text(subtitle(for: template))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        } header: {
            Text("Templates")
        } footer: {
            Text("Turned-on templates appear when you right-click an empty spot on the board, right after New Card.")
        }
    }

    private func subtitle(for template: CardTemplate) -> String {
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
