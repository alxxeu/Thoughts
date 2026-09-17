import Foundation

/// Действия из AI-подменю на карточке. `replacesText` определяет, что
/// делать с результатом — переписать содержимое карточки на месте или
/// дописать результат в конец (Continue writing).
enum AITextAction: CaseIterable {
    case summarize
    case rewrite
    case continueWriting
    case fixGrammar

    var title: String {
        switch self {
        case .summarize: return "Summarize"
        case .rewrite: return "Rewrite"
        case .continueWriting: return "Continue Writing"
        case .fixGrammar: return "Fix Grammar"
        }
    }

    var systemImage: String {
        switch self {
        case .summarize: return "text.line.first.and.arrowtriangle.forward"
        case .rewrite: return "arrow.triangle.2.circlepath"
        case .continueWriting: return "text.append"
        case .fixGrammar: return "checkmark.seal"
        }
    }

    var systemPrompt: String {
        let base: String
        switch self {
        case .summarize:
            base = "You summarize short personal notes. Reply with only the summary, no preamble, no quotes around it."
        case .rewrite:
            base = "You rewrite short personal notes to be clearer and more concise while preserving meaning and tone. Reply with only the rewritten text."
        case .continueWriting:
            base = "You continue short personal notes in the same voice and style. Reply with only the continuation text (do not repeat the original)."
        case .fixGrammar:
            base = "You fix spelling and grammar in short personal notes without changing meaning, tone, or wording choices beyond what's necessary. Reply with only the corrected text."
        }
        return base + " " + AISystemPromptRules.noMarkdown
    }

    /// Дописывается к существующему тексту, а не заменяет его.
    var appendsResult: Bool {
        self == .continueWriting
    }
}
