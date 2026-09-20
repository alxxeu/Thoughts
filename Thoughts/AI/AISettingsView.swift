import SwiftUI

/// Таб AI в Settings — в этой сборке провайдер один (Apple Intelligence,
/// on-device), выбирать не из чего, поэтому вместо пикера/ввода ключа —
/// просто статус доступности. BYOK для ChatGPT/Claude остаётся
/// Pro-эксклюзивом (см. AIProviderKind).
struct AISettingsTab: View {
    private var settings: AISettings { AISettings.shared }

    var body: some View {
        Form {
            Section {
                LabeledContent("Provider", value: "Apple Intelligence")
            } header: {
                Text("Provider")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Runs on-device and needs no API key.")
                    if let reason = AppleIntelligenceAvailability.unavailableReasonDescription {
                        Text(reason)
                    }
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
