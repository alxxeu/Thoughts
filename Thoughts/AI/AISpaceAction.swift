import Foundation

/// Системный промпт для Ask AI по всему Space (см. SpaceToolbar) — в
/// отличие от AICardPrompt, здесь на вход всегда идёт КОЛЛЕКЦИЯ заметок,
/// каждая в <note>…</note>: "---" внутри заметки — уже разделитель Markdown.
enum AISpaceAction {
    static let askSystemPrompt = """
    You answer a question using the user's personal notes as context. Each \
    note is wrapped in <note></note> tags and they appear before the \
    question. If the notes don't contain relevant information, say so \
    briefly rather than making things up. Reply with only the answer. \
    \(AISystemPromptRules.markdown)
    """
}
