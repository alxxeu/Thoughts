import SwiftUI
import UniformTypeIdentifiers

/// Settings → Plugins: плагины (пока заготовка — менеджера ещё нет), свои шаблоны
/// карточек (рабочие: импорт, экспорт, удаление) и каталог.
struct PluginsSettingsTab: View {
    var plugins = PluginsModel.shared
    var templates = UserTemplateStore.shared

    @State private var errorMessage: String?
    @State private var isDropTargeted = false

    private static let docsURL = URL(string: "https://github.com/alxxeu/Thoughts/blob/develop/docs/plugins.md")!

    var body: some View {
        Form {
            installedSection
            templatesSection
            catalogSection
        }
        .formStyle(.grouped)
        .onAppear { templates.reload() }
        .alert("Couldn\u{2019}t use this file", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
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
            SettingsHeader(category: "Plugins", title: "Installed")
        } footer: {
            Text("Plugins add fonts, themes and templates, and never run code. Installing is coming soon.")
        }
    }

    // MARK: - Свои шаблоны

    private var templatesSection: some View {
        Section {
            if templates.templates.isEmpty {
                Text("No templates yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(templates.templates) { stored in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stored.template.name)
                            Text(subtitle(for: stored.template))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Export\u{2026}") { export(stored) }
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([stored.url])
                        } label: { Image(systemName: "magnifyingglass") }
                            .help("Reveal in Finder")
                        Button(role: .destructive) {
                            templates.delete(stored)
                        } label: { Image(systemName: "trash") }
                            .help("Delete")
                    }
                    .buttonStyle(.borderless)
                }
            }
            SettingsRowButton(title: "Import Template\u{2026}") { importTemplates() }
        } header: {
            Text("My Templates")
        } footer: {
            Text("Right-click a card and choose Save as Template. Drop a .thoughtstemplate file here to import it. Your templates appear when you right-click an empty spot on the board.")
        }
        .dropDestination(for: URL.self) { urls, _ in
            importFiles(urls.filter { $0.pathExtension == UserTemplate.fileExtension })
            return true
        } isTargeted: { isDropTargeted = $0 }
        .opacity(isDropTargeted ? 0.6 : 1)
    }

    private func subtitle(for template: UserTemplate) -> String {
        let size = "\(template.columns)\u{00D7}\(template.rows)"
        return template.note.isEmpty ? size : "\(template.note) \u{00B7} \(size)"
    }

    private func export(_ stored: StoredTemplate) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.templateType]
        panel.nameFieldStringValue = stored.url.lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try templates.export(stored, to: url) } catch { errorMessage = error.localizedDescription }
    }

    private func importTemplates() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.templateType, .json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    private func importFiles(_ urls: [URL]) {
        for url in urls {
            do { try templates.importFile(at: url) } catch {
                errorMessage = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    private static var templateType: UTType {
        UTType(filenameExtension: UserTemplate.fileExtension) ?? .json
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
