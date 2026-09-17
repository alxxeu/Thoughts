import SwiftUI

/// Таб AI в Settings — BYOK: пользователь сам вводит свой ключ ChatGPT
/// или Claude, ключи живут в Keychain (AIKeyStore), не в UserDefaults.
struct AISettingsTab: View {
    private var settings: AISettings { AISettings.shared }

    // Черновики полей ключа — не пишем в Keychain на каждое нажатие
    // клавиши, только когда поле теряет фокус/меняется явно завершённым
    // значением. Инициализируются пустыми: реальный сохранённый ключ не
    // перечитывается обратно из Keychain для отображения (не показываем
    // секрет повторно), только правим/заменяем.
    @State private var openAIKeyDraft = ""
    @State private var anthropicKeyDraft = ""
    @FocusState private var focusedField: AIProviderKind?
    @State private var isShowingAPIKeysSheet = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Provider", selection: Binding(
                        get: { settings.selectedProvider },
                        set: { settings.selectedProvider = $0 }
                    )) {
                        ForEach(AIProviderKind.allCases) { provider in
                            Text(provider.displayName)
                                .tag(provider)
                                .disabled(!settings.hasKey(for: provider))
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("To select a provider for AI features, add an API key for it below.")
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
            // Иначе Form сам растягивается на всю доступную высоту таба
            // (окно Settings фиксированного размера), и кнопка ниже
            // добавляется уже ПОСЛЕ этого растяжения — вылезает за
            // пределы видимой области вместо того, чтобы просто идти
            // сразу под последней секцией.
            .fixedSize(horizontal: false, vertical: true)

            // ChatGPT/Claude API-ключи убраны в отдельный лист (тот же
            // паттерн, что "Add Printer, Scanner, or Fax…" в системных
            // Settings). Вынесено ЗА ПРЕДЕЛЫ Form целиком — .formStyle(.grouped)
            // сам оборачивает в рамку любой топ-level контент внутри Form,
            // даже без явного Section, так что иначе от рамки не избавиться.
            HStack {
                Spacer()
                Button("Add API Key…") {
                    isShowingAPIKeysSheet = true
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .sheet(isPresented: $isShowingAPIKeysSheet) {
            apiKeysSheet
        }
    }

    private var apiKeysSheet: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    apiKeyRow(for: .openAI, draft: $openAIKeyDraft)
                } header: {
                    Text("ChatGPT")
                } footer: {
                    keyFooter(for: .openAI)
                }

                Section {
                    apiKeyRow(for: .anthropic, draft: $anthropicKeyDraft)
                } header: {
                    Text("Claude")
                } footer: {
                    keyFooter(for: .anthropic)
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
        .frame(width: 420, height: 420)
    }

    @ViewBuilder
    private func apiKeyRow(for provider: AIProviderKind, draft: Binding<String>) -> some View {
        SecureField(
            settings.hasKey(for: provider) ? "Key saved — enter a new one to replace it" : "API Key",
            text: draft
        )
        .focused($focusedField, equals: provider)
        .onSubmit { commit(draft.wrappedValue, for: provider, draft: draft) }
        .onChange(of: focusedField) { oldValue, newValue in
            // Коммитим при потере фокуса этим конкретным полем — не хотим
            // писать в Keychain на каждое нажатие клавиши, но и не хотим
            // терять введённое, если просто кликнули в другое место.
            if oldValue == provider && newValue != provider {
                commit(draft.wrappedValue, for: provider, draft: draft)
            }
        }
        .textFieldStyle(.roundedBorder)

        TextField("Model", text: Binding(
            get: { settings.model(for: provider) },
            set: { newValue in
                switch provider {
                case .openAI: settings.openAIModel = newValue
                case .anthropic: settings.anthropicModel = newValue
                }
            }
        ))
        .textFieldStyle(.roundedBorder)

        if settings.hasKey(for: provider) {
            SettingsRowButton(title: "Remove Key") {
                settings.setAPIKey("", for: provider)
            }
        }
    }

    private func keyFooter(for provider: AIProviderKind) -> some View {
        HStack(spacing: 4) {
            Text(settings.hasKey(for: provider) ? "Key saved." : "No key saved yet.")
            Link("Get an API key", destination: provider.apiKeyHelpURL)
        }
    }

    private func commit(_ value: String, for provider: AIProviderKind, draft: Binding<String>) {
        guard !value.isEmpty else { return }
        settings.setAPIKey(value, for: provider)
        draft.wrappedValue = ""
    }
}
