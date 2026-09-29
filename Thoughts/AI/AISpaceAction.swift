import Foundation

/// Системный промпт для Ask AI по всему Space (см. ContentView.askAIPanel)
/// — в отличие от AICardPrompt, здесь на вход всегда идёт КОЛЛЕКЦИЯ
/// заметок, разделённых "---", а не одна карточка.
enum AISpaceAction {
    static let askSystemPrompt = """
    You answer a question using the user's personal notes as context. The \
    notes are separated by "---" and appear before the question. If the \
    notes don't contain relevant information, say so briefly rather than \
    making things up. Reply with only the answer. \(AISystemPromptRules.noMarkdown)
    """
}
