import Foundation

/// Свободный запрос к AI про ОДНУ карточку — панель Ask AI в Focus Mode
/// (см. CardView). В отличие от `AISpaceAction`, на вход идёт одна
/// заметка, а не коллекция через "---"; и в отличие от `AITextAction`,
/// формулировку задаёт пользователь, а не фиксированный пункт меню.
enum AICardPrompt {
    /// Запрос пользователя может быть и вопросом ("что я упустил?"), и
    /// инструкцией ("сделай дружелюбнее") — промпт покрывает оба случая.
    /// Поэтому здесь не переиспользуется `AISpaceAction.askSystemPrompt`:
    /// тот сформулирован строго как Q&A по набору заметок.
    static let systemPrompt = """
    You help the user with a single personal note. The note comes first, \
    followed by the user's request. Either answer the question or carry \
    out the instruction, and reply with only the result — no preamble, no \
    quotes around it. If the note doesn't contain what the request needs, \
    say so briefly rather than making things up. \(AISystemPromptRules.noMarkdown)
    """

    /// Примеры запросов, подставляемые в пустое поле как placeholder —
    /// подсказывают, что вообще можно попросить, вместо безликого
    /// "Ask about this card…".
    static let suggestions = [
        "Make this sound friendlier",
        "Summarize this card",
        "Pull out the key points",
        "Turn this into a checklist",
        "Rewrite this more concisely",
        "Explain this in simpler words",
        "What am I missing here?",
        "Fix the grammar"
    ]

    static func randomSuggestion() -> String {
        suggestions.randomElement() ?? "Ask about this card\u{2026}"
    }
}
