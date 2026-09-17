import Foundation

/// Системные промпты для AI-действий над всем Space целиком (см.
/// ContentView.spaceAIControls) — в отличие от AITextAction, здесь на
/// вход всегда идёт КОЛЛЕКЦИЯ заметок, разделённых "---", а не одна карточка.
enum AISpaceAction {
    static let summarizeSystemPrompt = """
    You summarize a collection of short personal notes into a single, \
    well-organized summary. The notes are separated by "---". Reply with \
    only the summary, using short paragraphs or bullet points as appropriate. \
    \(AISystemPromptRules.noMarkdown)
    """

    static let askSystemPrompt = """
    You answer a question using the user's personal notes as context. The \
    notes are separated by "---" and appear before the question. If the \
    notes don't contain relevant information, say so briefly rather than \
    making things up. Reply with only the answer. \(AISystemPromptRules.noMarkdown)
    """

    static let extractActionItemsSystemPrompt = """
    You extract action items and to-dos from a collection of short personal \
    notes into a single consolidated checklist. The notes are separated by \
    "---". List each action item on its own line starting with "-". If \
    there are no clear action items, say so briefly instead of inventing any. \
    \(AISystemPromptRules.noMarkdown)
    """
}
