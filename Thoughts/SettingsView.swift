import SwiftUI
import ServiceManagement

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
                    }
                    .formStyle(.grouped)
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }

                    SecuritySettingsTab(viewModel: viewModel)
                        .tabItem {
                            Label("Security", systemImage: "lock.shield")
                        }
                }
                .frame(width: 460, height: 420)
            }
        }
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
