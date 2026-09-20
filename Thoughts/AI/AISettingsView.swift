import SwiftUI

/// Таб AI в Settings. ChatGPT/Claude показаны в пикере как тизер Pro —
/// строки задизейблены через AISettings.hasKey(for:) (всегда false для
/// обоих на этой сборке), кнопка "Add API Key…" видна, но недоступна.
/// Реальная BYOK-инфраструктура (Keychain, HTTP-клиенты) — только на
/// feature/pro-subscription.
struct AISettingsTab: View {
    private var settings: AISettings { AISettings.shared }

    var body: some View {
        Form {
            Section {
                Picker("", selection: Binding(
                    get: { settings.selectedProvider },
                    set: { settings.selectedProvider = $0 }
                )) {
                    ForEach(AIProviderKind.allCases) { provider in
                        Text(provider.displayName)
                            .tag(provider)
                            .disabled(!settings.hasKey(for: provider))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Provider")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Intelligence runs on-device and needs no API key.")
                    if let reason = AppleIntelligenceAvailability.unavailableReasonDescription {
                        Text(reason)
                    }
                }
            }

            Section {
                SettingsRowButton(title: "Add API Key\u{2026}") {}
                    .disabled(true)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bringing your own ChatGPT or Claude API key will be available later in a Pro subscription.")
                    Button("Learn more") {
                        SettingsNavigator.shared.selectedTab = .pro
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            Section {
                Picker("Send Message With", selection: Binding(
                    get: { settings.sendKeyBinding },
                    set: { settings.sendKeyBinding = $0 }
                )) {
                    ForEach(AISendKeyBinding.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Keyboard")
            } footer: {
                Text(settings.sendKeyBinding.description)
            }
        }
        .formStyle(.grouped)
    }
}
