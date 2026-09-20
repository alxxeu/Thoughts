import Foundation

/// Какой AI-провайдер сейчас активен. В этой сборке — только Apple
/// Intelligence (BYOK для ChatGPT/Claude остаётся Pro-эксклюзивом, живёт
/// только на ветке feature/pro-subscription). Форма enum'а (с одним
/// case'ом вместо трёх) сохранена намеренно — при будущем объединении
/// веток/появлении реального entitlement-слоя достаточно дописать case'ы
/// обратно, а не переписывать архитектуру.
enum AIProviderKind: String, CaseIterable, Identifiable, Codable {
    case appleIntelligence

    var id: String { rawValue }

    var displayName: String {
        "Apple Intelligence"
    }

    /// У Apple Intelligence выбора модели нет вообще (одна on-device модель).
    var defaultModel: String {
        "on-device"
    }

    /// Apple Intelligence работает on-device через FoundationModels, ключ
    /// не нужен вообще — её "настроенность" определяется доступностью на
    /// Mac (см. AppleIntelligenceAvailability), а не Keychain.
    var requiresAPIKey: Bool { false }

    var apiKeyHelpURL: URL? { nil }
}
