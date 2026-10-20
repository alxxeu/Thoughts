import SwiftUI
import ServiceManagement

/// Обычная кнопка внутри Form/Section на macOS получает собственную
/// светло-серую капсулу вокруг текста — .buttonStyle(.plain) убирает её, а
/// Spacer + contentShape делают кликабельной всю строку целиком, а не
/// только текст. Общий компонент для General (здесь) и Security
/// (SecuritySettingsView) табов — раньше было продублировано в обоих.
struct SettingsRowButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    var viewModel: BoardViewModel

    // Проверяем текущий статус автозапуска в системе при загрузке
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var isShowingReleaseNotes = false

    var body: some View {
        Group {
            if viewModel.isActiveSpaceLocked {
                // Основной барьер против побега из заблокированного Space
                // в Settings: .disabled() на пункте меню в ThoughtsApp
                // ненадёжен как единственная защита (Commands не всегда
                // обновляются мгновенно), а здесь содержимое окна физически
                // не существует, пока активный Space заблокирован — так же,
                // как карточки не существуют под SpaceLockOverlayView.
                lockedPlaceholder
                    .frame(width: Self.windowSize.width, height: Self.windowSize.height)
            } else {
                splitView
                    .frame(width: Self.windowSize.width, height: Self.windowSize.height)
            }
        }
    }

    /// Нативный NavigationSplitView с боковой панелью — как в настройках Thaw и
    /// системных (List(.sidebar), Label + tag, заголовок раздела в панели окна).
    private var splitView: some View {
        NavigationSplitView {
            sidebar
                .background(SidebarLimits())
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
        } detail: {
            detail
                .id(SettingsNavigation.shared.selectedTab)
                .navigationTitle("Settings")
                .fullHeightToolbar()
        }
        .toolbar { navigationButtons }
    }

    /// ‹ › в панели окна — по разделам подряд, как у Thaw.
    @ToolbarContentBuilder
    private var navigationButtons: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(currentIndex == 0)
            .help("Back")

            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(currentIndex == SettingsNavigation.Tab.allCases.count - 1)
            .help("Forward")
        }
    }

    private static let windowSize = CGSize(width: 900, height: 640)

    /// Группы разделов в боковой панели (между группами — стандартный отступ списка).
    private static let tabGroups: [[SettingsNavigation.Tab]] = [
        [.general, .appearance], [.security, .shortcuts], [.ai, .plugins], [.about]
    ]

    private var sidebar: some View {
        List(selection: Binding<SettingsNavigation.Tab?>(
            get: { SettingsNavigation.shared.selectedTab },
            set: { if let tab = $0 { SettingsNavigation.shared.selectedTab = tab } }
        )) {
            ForEach(Array(Self.tabGroups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group, id: \.self) { tab in
                        Label(Self.title(for: tab), systemImage: Self.symbol(for: tab))
                            .tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var currentIndex: Int {
        SettingsNavigation.Tab.allCases.firstIndex(of: SettingsNavigation.shared.selectedTab) ?? 0
    }

    /// ‹ › в панели окна — по разделам подряд, как у Thaw.
    private func step(_ delta: Int) {
        let tabs = SettingsNavigation.Tab.allCases
        let index = currentIndex + delta
        guard tabs.indices.contains(index) else { return }
        SettingsNavigation.shared.selectedTab = tabs[index]
    }

    @ViewBuilder
    private var detail: some View {
        switch SettingsNavigation.shared.selectedTab {
        case .general: generalTab
        case .appearance: AppearanceSettingsTab(settings: viewModel.appearanceSettings)
        case .security: SecuritySettingsTab(viewModel: viewModel)
        case .shortcuts: ShortcutsSettingsTab()
        case .ai: AISettingsTab()
        case .plugins: PluginsSettingsTab()
        case .about: aboutTab
        }
    }

    private static func title(for tab: SettingsNavigation.Tab) -> String {
        switch tab {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .security: return "Security"
        case .shortcuts: return "Shortcuts"
        case .ai: return "AI"
        case .plugins: return "Plugins"
        case .about: return "About"
        }
    }

    private static func symbol(for tab: SettingsNavigation.Tab) -> String {
        switch tab {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .security: return "shield.lefthalf.filled"
        case .shortcuts: return "command.square.fill"
        case .ai: return symbol("sparkles.2", fallback: "sparkles")
        case .plugins: return "puzzlepiece.extension.fill"
        case .about: return symbol("info.app.fill", fallback: "info.circle.fill")
        }
    }

    private var generalTab: some View {
            Form {
                Section {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, newValue in
                            updateLaunchAtLogin(enabled: newValue)
                        }
                } header: {
                    SettingsHeader(category: "General", title: "Startup")
                }

                Section {
                    Toggle("Desktop Overlay", isOn: Binding(
                        get: { viewModel.desktopOverlay.isEnabled },
                        set: { viewModel.desktopOverlay.isEnabled = $0 }
                    ))
                    .toggleStyle(.switch)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Runs best on macOS 26 or later.", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text("Keeps Thoughts sitting just above your Desktop icons instead of a normal window. Press \u{2325}D in any app to show the Desktop; switch to any Space (\u{2325}1\u{2013}9) to come back. From any other app, use \u{2303}\u{2325}1\u{2013}9.")
                    }
                }

                ICloudSyncSection(viewModel: viewModel)

                BackupSection(viewModel: viewModel)

                Section {
                    SettingsRowButton(title: "Replay Onboarding") {
                        NotificationCenter.default.post(name: .replayOnboarding, object: nil)
                    }
                } footer: {
                    Text("Show the first-launch tour of Thoughts again.")
                }
            }
            .formStyle(.grouped)
    }

    private var aboutTab: some View {
            Form {
                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Author", value: "Aleksei Trofimov")
                    SettingsRowButton(title: "Release Notes\u{2026}") {
                        isShowingReleaseNotes = true
                    }
                    CheckForUpdatesRow()
                } header: {
                    SettingsHeader(category: "About", title: "Thoughts")
                }

                Section {
                    Link(destination: URL(string: "https://github.com/alxxeu/Thoughts")!) {
                        HStack {
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://t.me/thoughtsapp")!) {
                        HStack {
                            Text("Telegram Channel")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "mailto:alxxeu.dev@proton.me")!) {
                        HStack {
                            Text("Email")
                            Spacer()
                            Text("alxxeu.dev@proton.me")
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Follow for updates and release notes.")
                }
            }
            .formStyle(.grouped)
            .sheet(isPresented: $isShowingReleaseNotes) {
                ReleaseNotesView()
            }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// sparkles.2 есть с macOS 26, info.app.fill — с macOS 27; на старых
    /// системах вкладка осталась бы без иконки.
    private static func symbol(_ name: String, fallback: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : fallback
    }

    private var lockedPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("Unlock the current Space to access Settings")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                // Регистрируем приложение в автозапуске macOS
                try SMAppService.mainApp.register()
            } else {
                // Удаляем из автозапуска
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Ошибка изменения статуса автозапуска: \(error.localizedDescription)")
            // В случае ошибки возвращаем тумблер в актуальное состояние
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}
