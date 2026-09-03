import SwiftUI
import ServiceManagement

struct SettingsView: View {
    // Проверяем текущий статус автозапуска в системе при загрузке
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        TabView {
            Form {
                Section {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, newValue in
                            updateLaunchAtLogin(enabled: newValue)
                        }
                }
            }
            .padding(20)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
        }
        .frame(width: 420, height: 220)
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
