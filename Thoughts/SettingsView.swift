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
                    .frame(width: 460, height: 480)
            } else {
                TabView(selection: Binding(
                    get: { SettingsNavigation.shared.selectedTab },
                    set: { SettingsNavigation.shared.selectedTab = $0 }
                )) {
                    Form {
                        Section {
                            Toggle("Launch at Login", isOn: $launchAtLogin)
                                .toggleStyle(.switch)
                                .onChange(of: launchAtLogin) { _, newValue in
                                    updateLaunchAtLogin(enabled: newValue)
                                }
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
                    .tabItem {
                        Label("General", systemImage: "gearshape.fill")
                    }
                    .tag(SettingsNavigation.Tab.general)

                    AppearanceSettingsTab(settings: viewModel.appearanceSettings)
                        .tabItem {
                            Label("Appearance", systemImage: "paintbrush.fill")
                        }
                        .tag(SettingsNavigation.Tab.appearance)

                    PluginsSettingsTab()
                        .tabItem {
                            Label("Plugins", systemImage: "puzzlepiece.extension.fill")
                        }
                        .tag(SettingsNavigation.Tab.plugins)

                    SecuritySettingsTab(viewModel: viewModel)
                        .tabItem {
                            Label("Security", systemImage: "shield.lefthalf.filled")
                        }
                        .tag(SettingsNavigation.Tab.security)

                    ShortcutsSettingsTab()
                        .tabItem {
                            Label("Shortcuts", systemImage: "command.square.fill")
                        }
                        .tag(SettingsNavigation.Tab.shortcuts)

                    AISettingsTab()
                        .tabItem {
                            Label("AI", systemImage: Self.symbol("sparkles.2", fallback: "sparkles"))
                        }
                        .tag(SettingsNavigation.Tab.ai)

                    Form {
                        Section {
                            LabeledContent("Version", value: appVersion)
                            LabeledContent("Author", value: "Aleksei Trofimov")
                            SettingsRowButton(title: "Release Notes\u{2026}") {
                                isShowingReleaseNotes = true
                            }
                            CheckForUpdatesRow()
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
                    .tabItem {
                        Label("About", systemImage: Self.symbol("info.app.fill", fallback: "info.circle.fill"))
                    }
                    .tag(SettingsNavigation.Tab.about)
                }
                .frame(width: 460, height: 480)
            }
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
