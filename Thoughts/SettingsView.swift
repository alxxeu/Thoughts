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
                    .frame(width: 460, height: 420)
            } else {
                TabView {
                    Form {
                        Section {
                            Toggle("Launch at Login", isOn: $launchAtLogin)
                                .toggleStyle(.switch)
                                .onChange(of: launchAtLogin) { _, newValue in
                                    updateLaunchAtLogin(enabled: newValue)
                                }
                        }

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
                        Label("General", systemImage: "gearshape")
                    }

                    Form {
                        Section {
                            Picker("Theme", selection: Binding(
                                get: { viewModel.appearanceSettings.colorScheme },
                                set: { viewModel.appearanceSettings.colorScheme = $0 }
                            )) {
                                ForEach(AppColorScheme.allCases) { scheme in
                                    Text(scheme.title).tag(scheme)
                                }
                            }
                            .pickerStyle(.segmented)
                        } footer: {
                            Text("Auto follows your Mac's system appearance.")
                        }
                    }
                    .formStyle(.grouped)
                    .tabItem {
                        Label("Appearance", systemImage: "paintbrush")
                    }

                    SecuritySettingsTab(viewModel: viewModel)
                        .tabItem {
                            Label("Security", systemImage: "lock.shield")
                        }

                    Form {
                        Section {
                            LabeledContent("Version", value: appVersion)
                            LabeledContent("Author", value: "Aleksei Trofimov")
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
                        } footer: {
                            Text("Follow for updates and release notes.")
                        }
                    }
                    .formStyle(.grouped)
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
                }
                .frame(width: 460, height: 420)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
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
