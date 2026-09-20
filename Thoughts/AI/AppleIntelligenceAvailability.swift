import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Доступность Apple Intelligence на этом Mac. SDK всегда таскает
/// объявления FoundationModels независимо от версии реальной ОС, так что
/// проверка на этапе выполнения идёт через #available, а не только
/// #if canImport — иначе на macOS < 26 приложение упадёт при обращении
/// к SystemLanguageModel.
enum AppleIntelligenceAvailability {
    static var isAvailable: Bool {
        guard #available(macOS 26.0, *) else { return false }
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    /// nil, если провайдер готов к использованию прямо сейчас.
    static var unavailableReasonDescription: String? {
        guard #available(macOS 26.0, *) else {
            return "Apple Intelligence requires macOS 26 or later."
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This Mac doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings → Apple Intelligence & Siri."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still preparing the on-device model — try again shortly."
        case .unavailable:
            return "Apple Intelligence is unavailable on this Mac."
        }
    }
}
