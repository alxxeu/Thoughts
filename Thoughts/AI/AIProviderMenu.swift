import SwiftUI

/// Переключатель провайдера AI прямо в панелях Ask AI (Space, Focus Mode,
/// контекстное меню текста) — без похода в Settings. Меняет общую
/// настройку AISettings.selectedProvider: она одна на все панели и та же,
/// что в Settings → AI, чтобы всегда было ясно, кто сейчас отвечает.
///
/// Выбрать можно только провайдера, который реально сработает
/// (AISettings.hasKey): Apple Intelligence — если она доступна на этом Mac,
/// ChatGPT/Claude — если задан API-ключ.
struct AIProviderMenu: View {
    enum Style {
        /// Светлый текст — для тёмных панелей Space и Focus Mode.
        case onDark
        /// Системные цвета — для popover контекстного Ask AI.
        case system
    }

    var style: Style = .onDark
    private let settings = AISettings.shared

    var body: some View {
        Menu {
            ForEach(AIProviderKind.allCases) { provider in
                Button {
                    settings.selectedProvider = provider
                } label: {
                    if provider == settings.selectedProvider {
                        Label(title(for: provider), systemImage: "checkmark")
                    } else {
                        Text(title(for: provider))
                    }
                }
                .disabled(!settings.hasKey(for: provider))
            }
            Divider()
            Button("AI Settings\u{2026}") {
                SettingsNavigation.shared.open(.ai)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: Self.symbol(for: settings.selectedProvider))
                    .font(.system(size: 10))
                Text(Self.shortName(for: settings.selectedProvider))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(style == .onDark ? AnyShapeStyle(Color.white.opacity(0.7)) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(style == .onDark ? Color.white.opacity(0.1) : Color.primary.opacity(0.06))
            )
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .help("AI provider")
    }

    private func title(for provider: AIProviderKind) -> String {
        guard !settings.hasKey(for: provider) else { return provider.displayName }
        switch provider {
        case .appleIntelligence: return "\(provider.displayName) \u{2014} not available on this Mac"
        case .openAI, .anthropic: return "\(provider.displayName) \u{2014} add an API key in Settings"
        }
    }

    static func shortName(for provider: AIProviderKind) -> String {
        switch provider {
        case .appleIntelligence: return "Apple"
        case .openAI: return "ChatGPT"
        case .anthropic: return "Claude"
        }
    }

    /// Нейтральные SF Symbols — без чужих логотипов, кроме системного Apple.
    static func symbol(for provider: AIProviderKind) -> String {
        switch provider {
        case .appleIntelligence: return "apple.logo"
        case .openAI: return "bubble.left"
        case .anthropic: return "sparkles"
        }
    }
}

/// Заглушка вместо поля вопроса, когда выбранный провайдер недоступен
/// (ключ удалили, ещё не доехал через iCloud Keychain…).
struct AIUnavailableNotice: View {
    var style: AIProviderMenu.Style = .onDark
    /// В панелях без заголовка (Space, Focus Mode) переключатель
    /// показывается прямо здесь — иначе выбрать другого провайдера негде.
    var showsProviderMenu = false
    private let settings = AISettings.shared

    private var hasAnyProvider: Bool {
        AIProviderKind.allCases.contains { settings.hasKey(for: $0) }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(hasAnyProvider ? "Choose an available AI provider to ask a question." : "Set up AI to ask about your notes.")
                .font(.system(size: 12))
                .foregroundStyle(style == .onDark ? AnyShapeStyle(Color.white.opacity(0.6)) : AnyShapeStyle(.secondary))
                .multilineTextAlignment(.center)
            if hasAnyProvider && showsProviderMenu {
                AIProviderMenu(style: style)
            }
            if !hasAnyProvider {
                Button("Open Settings") {
                    SettingsNavigation.shared.open(.ai)
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
    }
}
