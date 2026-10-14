import Foundation

/// Общие для всех AI-промптов (карточных и Space-level) правила формата
/// ответа. Текст карточек — Markdown (см. MarkdownStyler), поэтому модель
/// просим писать ровно тем набором, который карточки умеют отображать.
enum AISystemPromptRules {
    static let markdown = """
    Format the reply in Markdown, using only: **bold**, *italic*, \
    ~~strikethrough~~, ==highlight==, `inline code`, [text](url) links, \
    #, ## and ### headings, "- " bullet lists, "1. " numbered lists, \
    "- [ ] " checklists, "> " quotes, ``` code blocks and "---" dividers. \
    Do not use tables, nested lists, HTML, footnotes or images. Use \
    formatting only where it helps; a short answer can be plain sentences.
    """
}

extension AttributedString {
    /// Ответ AI в превью до вставки в карточку: жирный, курсив,
    /// зачёркивание, код и ссылки видны сразу; остальная разметка (`==`,
    /// `#`, списки) показывается символами и отрисуется уже в карточке.
    static func aiAnswerPreview(_ answer: String) -> AttributedString {
        (try? AttributedString(markdown: answer, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(answer)
    }
}
