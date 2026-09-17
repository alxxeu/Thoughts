import Foundation

/// Общие для всех AI-промптов (карточных и Space-level) правила формата
/// ответа. Карточки — обычный plain text (CardNSTextView), без движка
/// для рендеринга Markdown — модель нужно явно попросить не использовать
/// разметку, иначе `**`/`##` попадают в текст карточки буквально.
enum AISystemPromptRules {
    static let noMarkdown = """
    Do not use Markdown formatting — no **bold**, no # headings, no \
    backticks. Reply in plain text only; for lists, start each item on \
    its own line with a plain "-".
    """
}
