import SwiftUI
import AppKit

/// "Ask AI" из контекстного меню текста карточки — компактный popover у
/// выделения (или у места клика): свободный вопрос про выделенный текст
/// либо всю карточку, ответ и действия Replace / Insert Below / Copy /
/// Ask Again.
///
/// Вставка и замена идут через сам NSTextView (insertText:replacementRange:)
/// — работает ⌘Z, а card.text/formattingData синхронизируются обычным путём
/// через textDidChange (см. CardTextView.Coordinator).
final class AskAIPopoverController: NSObject, NSPopoverDelegate {
    /// Открыт не больше одного popover за раз.
    private static var current: AskAIPopoverController?

    private let popover = NSPopover()
    private weak var textView: NSTextView?
    private let range: NSRange
    private let model: AskAIModel

    /// - Parameters:
    ///   - range: выделение, про которое спрашивают; длина 0 — вся карточка.
    ///   - anchor: прямоугольник в координатах textView, к которому
    ///     привязан popover.
    static func show(for textView: NSTextView, range: NSRange, anchor: NSRect) {
        current?.popover.performClose(nil)
        let controller = AskAIPopoverController(textView: textView, range: range)
        current = controller
        controller.popover.show(relativeTo: anchor, of: textView, preferredEdge: .maxY)
    }

    private init(textView: NSTextView, range: NSRange) {
        self.textView = textView
        self.range = range
        let text = textView.string as NSString
        let hasSelection = range.length > 0 && NSMaxRange(range) <= text.length
        let context = hasSelection ? text.substring(with: range) : textView.string
        model = AskAIModel(
            // Разделитель — символ-заглушка U+FFFC, AI он ни к чему.
            context: context.replacingOccurrences(of: "\u{FFFC}", with: "---"),
            isAboutSelection: hasSelection
        )
        super.init()

        let hosting = NSHostingController(rootView: AskAIPopoverView(
            model: model,
            onReplace: { [weak self] in self?.replace() },
            onInsertBelow: { [weak self] in self?.insertBelow() },
            onClose: { [weak self] in self?.popover.performClose(nil) }
        ))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self
    }

    func popoverDidClose(_ notification: Notification) {
        if Self.current === self {
            Self.current = nil
        }
    }

    // MARK: - Actions

    private func replace() {
        guard let textView, let answer = model.answer else { return }
        let length = (textView.string as NSString).length
        let target = model.isAboutSelection && NSMaxRange(range) <= length
            ? range
            : NSRange(location: 0, length: length)
        apply(answer, at: target, in: textView)
    }

    private func insertBelow() {
        guard let textView, let answer = model.answer else { return }
        let length = (textView.string as NSString).length
        let location = model.isAboutSelection && NSMaxRange(range) <= length ? NSMaxRange(range) : length
        let prefix = length == 0 ? "" : "\n\n"
        apply(prefix + answer, at: NSRange(location: location, length: 0), in: textView)
    }

    private func apply(_ text: String, at range: NSRange, in textView: NSTextView) {
        popover.performClose(nil)
        textView.window?.makeFirstResponder(textView)
        textView.insertText(text, replacementRange: range)
    }
}

// MARK: - Model

@Observable
final class AskAIModel {
    let context: String
    let isAboutSelection: Bool

    var question = ""
    var askedQuestion = ""
    var answer: String?
    var errorMessage: String?
    var isBusy = false
    var placeholder = AICardPrompt.randomSuggestion()

    init(context: String, isAboutSelection: Bool) {
        self.context = context
        self.isAboutSelection = isAboutSelection
    }

    func ask() {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isBusy else { return }
        askedQuestion = question
        errorMessage = nil
        isBusy = true
        let context = context
        let isAboutSelection = isAboutSelection
        Task {
            do {
                let service = try AITextServiceFactory.makeActiveService()
                let label = isAboutSelection ? "Selected text from a note" : "Note"
                let userText = context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? question
                    : "\(label):\n\(context)\n\nRequest: \(question)"
                let result = try await service.generate(systemPrompt: AICardPrompt.systemPrompt, userText: userText)
                answer = result
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    func reset() {
        answer = nil
        errorMessage = nil
        question = ""
        placeholder = AICardPrompt.randomSuggestion()
    }
}

// MARK: - View

private struct AskAIPopoverView: View {
    var model: AskAIModel
    var onReplace: () -> Void
    var onInsertBelow: () -> Void
    var onClose: () -> Void

    private let settings = AISettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(model.isAboutSelection ? "About the selection" : "About this card", systemImage: "sparkle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                AIProviderMenu(style: .system)
            }

            if !settings.hasKey(for: settings.selectedProvider) {
                AIUnavailableNotice(style: .system)
            } else if let answer = model.answer {
                answerView(answer)
            } else {
                questionView
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private var questionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            AIPromptTextView(
                text: Binding(get: { model.question }, set: { model.question = $0 }),
                shouldFocus: true,
                onSend: { model.ask() },
                font: .systemFont(ofSize: 13),
                textColor: .labelColor,
                onEscape: onClose
            )
            .frame(height: 64)
            .overlay(alignment: .topLeading) {
                if model.question.isEmpty {
                    Text(model.placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 11)
                        .padding(.top, 6)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))

            HStack(spacing: 8) {
                if let error = model.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                if model.isBusy {
                    ProgressView().controlSize(.small)
                }
                Button {
                    model.ask()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(model.isBusy || model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(model.errorMessage == nil ? "Ask" : "Try Again")
            }
        }
    }

    private func answerView(_ answer: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.askedQuestion)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            ScrollView {
                Text(answer)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                chip("Replace", systemImage: "arrow.triangle.2.circlepath", action: onReplace)
                chip("Insert Below", systemImage: "text.insert", action: onInsertBelow)
                chip("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(answer, forType: .string)
                    onClose()
                }
                Spacer(minLength: 0)
                Button {
                    model.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Ask Again")
            }
        }
    }

    private func chip(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
