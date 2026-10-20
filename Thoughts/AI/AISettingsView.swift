import SwiftUI

/// Таб AI в Settings — BYOK: пользователь сам вводит свой ключ провайдера,
/// ключи живут в Keychain (AIKeyStore), не в UserDefaults.
struct AISettingsTab: View {
    private var settings: AISettings { AISettings.shared }

    // Черновики полей ключа — не пишем в Keychain на каждое нажатие
    // клавиши, только когда поле теряет фокус/меняется явно завершённым
    // значением. Сохранённый ключ обратно не показываем, только заменяем.
    @State private var keyDrafts: [AIProviderKind: String] = [:]
    @FocusState private var focusedField: AIProviderKind?
    @State private var isShowingAPIKeysSheet = false

    var body: some View {
            Form {
                Section {
                    // nil — Disabled: AI выключен, входов в Ask AI нет.
                    Picker("", selection: Binding<AIProviderKind?>(
                        get: { settings.isEnabled ? settings.selectedProvider : nil },
                        set: { provider in
                            if let provider {
                                settings.selectedProvider = provider
                                settings.isEnabled = true
                            } else {
                                settings.isEnabled = false
                            }
                        }
                    )) {
                        Text("Disabled")
                            .tag(AIProviderKind?.none)
                        ForEach(AIProviderKind.allCases) { provider in
                            Text(provider.displayName)
                                .tag(AIProviderKind?.some(provider))
                                .disabled(!settings.hasKey(for: provider))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Provider")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Intelligence runs on-device and Ollama runs on this Mac \u{2014} neither needs a key. Other providers need an API key \u{2014} add one below.")
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
                .disabled(!settings.isEnabled)

                // API-ключи — в отдельном листе (как "Add Printer, Scanner,
                // or Fax…" в системных Settings).
                Section {
                    SettingsRowButton(title: "Add API Key\u{2026}") {
                        isShowingAPIKeysSheet = true
                    }
                }
            }
            .formStyle(.grouped)
        .sheet(isPresented: $isShowingAPIKeysSheet) {
            apiKeysSheet
        }
    }

    private var apiKeysSheet: some View {
        VStack(spacing: 0) {
            Form {
                ForEach(AIProviderKind.configurable) { provider in
                    Section {
                        apiKeyRow(for: provider)
                    } header: {
                        Text(provider.displayName)
                    } footer: {
                        keyFooter(for: provider)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    isShowingAPIKeysSheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460, height: 560)
    }

    @ViewBuilder
    private func apiKeyRow(for provider: AIProviderKind) -> some View {
        if provider.needsAPIKey {
            let draft = Binding(
                get: { keyDrafts[provider] ?? "" },
                set: { keyDrafts[provider] = $0 }
            )
            SecureField(
                settings.hasKey(for: provider) ? "Key saved \u{2014} enter a new one to replace it" : "API Key",
                text: draft
            )
            .focused($focusedField, equals: provider)
            .onSubmit { commit(for: provider) }
            .onChange(of: focusedField) { oldValue, newValue in
                // Коммитим при потере фокуса этим конкретным полем — не хотим
                // писать в Keychain на каждое нажатие клавиши, но и не хотим
                // терять введённое, если просто кликнули в другое место.
                if oldValue == provider && newValue != provider {
                    commit(for: provider)
                }
            }
            .textFieldStyle(.roundedBorder)
        }

        TextField("Model", text: Binding(
            get: { settings.model(for: provider) },
            set: { settings.setModel($0, for: provider) }
        ))
        .textFieldStyle(.roundedBorder)

        if provider.needsAPIKey, settings.hasKey(for: provider) {
            SettingsRowButton(title: "Remove Key") {
                settings.setAPIKey("", for: provider)
            }
        }
    }

    private func keyFooter(for provider: AIProviderKind) -> some View {
        HStack(spacing: 4) {
            if provider.needsAPIKey {
                Text(settings.hasKey(for: provider) ? "Key saved." : "No key saved yet.")
                if let helpURL = provider.apiKeyHelpURL {
                    Link("Get an API key", destination: helpURL)
                }
            } else {
                Text("Runs locally, no key needed.")
                if let helpURL = provider.apiKeyHelpURL {
                    Link("Download Ollama", destination: helpURL)
                }
            }
        }
    }

    private func commit(for provider: AIProviderKind) {
        guard let value = keyDrafts[provider], !value.isEmpty else { return }
        settings.setAPIKey(value, for: provider)
        keyDrafts[provider] = ""
    }
}
