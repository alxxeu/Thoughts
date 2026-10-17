import SwiftUI
import UIKit

/// Редактор карточки на iPhone с живым Markdown: UITextView на TextKit 1
/// (LiveLayoutManager рисует блоки), оформление — LiveMarkdownStyler, правила
/// курсора и Backspace — LiveMarkdown. В `text` — обычный Markdown.
/// Сам не прокручивается — растёт по тексту внутри ScrollView SwiftUI: системное
/// размытие края под шапкой (safeAreaBar) SwiftUI рисует только для своих
/// ScrollView; UIKit-прокрутке внутри шторки его не дал ни один способ.
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let controller: MarkdownEditorController
    /// Не ниже видимой области — тап по пустому месту под текстом ставит курсор.
    var minHeight: CGFloat = 0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: max(height, minHeight))
    }

    func makeUIView(context: Context) -> UITextView {
        let storage = NSTextStorage()
        let layout = LiveLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let view = MarkdownUITextView(frame: .zero, textContainer: container)
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 16, bottom: 120, right: 16)
        view.isScrollEnabled = false
        view.keyboardAppearance = .dark
        view.tintColor = LiveMarkdownStyler.accent
        // Умные кавычки и тире ломали бы разметку.
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.delegate = context.coordinator
        view.text = text
        context.coordinator.restyle(view)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        controller.textView = view
        controller.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        // Текст сменился снаружи (синк) — подставить, сохранив курсор.
        guard view.text != text, view.markedTextRange == nil else { return }
        let selection = view.selectedRange
        view.text = text
        context.coordinator.restyle(view)
        let length = (text as NSString).length
        view.selectedRange = NSRange(location: min(selection.location, length), length: 0)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: MarkdownTextView
        private var atoms: [LiveMarkdown.Atom] = []
        /// Разбор текущего текста — один на правку; его берут панель, Backspace и Return.
        private var paragraphs: [MarkdownStyler.Paragraph] = []
        private var isSnapping = false
        /// Правку вносит сам редактор (Backspace, Return, панель) — не перехватывать её снова.
        var isApplying = false
        /// Идёт правка текста: курсор UIKit сдвигает раньше, чем приходит новый текст, и
        /// по старой разметке его утягивало назад (второй Return в коде не попадал на пустую строку).
        private var isEditing = false

        init(_ parent: MarkdownTextView) { self.parent = parent }

        func restyle(_ view: UITextView) {
            guard view.markedTextRange == nil else { return } // идёт набор с подсказками — не мешать
            paragraphs = LiveMarkdownStyler.style(view.textStorage)
            atoms = LiveMarkdown.atoms(paragraphs, length: view.textStorage.length)
            if let pending = parent.controller.pendingPair, NSMaxRange(pending) <= view.textStorage.length {
                LiveMarkdownStyler.hide(pending, in: view.textStorage)
                let middle = pending.location + pending.length / 2
                atoms.append(.init(lower: pending.location, upper: NSMaxRange(pending), target: middle))
            }
            // Набор продолжается обычным шрифтом; оформление дорисует перекраска.
            view.typingAttributes = LiveMarkdownStyler.baseAttributes
            parent.controller.update(selection: view.selectedRange, text: view.text, paragraphs: paragraphs)
        }

        // MARK: Правки

        func textViewDidChange(_ view: UITextView) {
            isEditing = false
            parent.controller.textDidChange(view.text)
            parent.text = view.text
            restyle(view)
            snap(view)
        }

        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard !isApplying, view.markedTextRange == nil, view.selectedRange.length == 0 else { return true }
            if text.isEmpty, range.length == 1,
               let delete = LiveMarkdown.backspaceRange(at: NSMaxRange(range), text: view.text, paragraphs: paragraphs), delete != range {
                parent.controller.apply(.init(range: delete, replacement: "", selection: NSRange(location: delete.location, length: 0)))
                return false
            }
            if text == "\n", let edit = LiveMarkdown.newline(at: range.location, text: view.text, paragraphs: paragraphs) {
                parent.controller.apply(edit)
                return false
            }
            isEditing = true
            return true
        }

        // MARK: Курсор

        func textViewDidChangeSelection(_ view: UITextView) {
            guard !isSnapping, !isEditing else { return }
            snap(view)
            parent.controller.update(selection: view.selectedRange, text: view.text, paragraphs: paragraphs)
        }

        /// Курсор не встаёт внутрь скрытых символов.
        private func snap(_ view: UITextView) {
            let selection = view.selectedRange
            guard selection.length == 0 else { return }
            let target = LiveMarkdown.snap(selection.location, atoms: atoms)
            guard target != selection.location else { return }
            isSnapping = true
            view.selectedRange = NSRange(location: target, length: 0)
            isSnapping = false
        }

        func textViewDidBeginEditing(_ view: UITextView) { parent.isFocused = true }
        func textViewDidEndEditing(_ view: UITextView) { parent.isFocused = false }

        // MARK: Квадратики чек-листа

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? UITextView else { return }
            let point = gesture.location(in: view)
            if let url = link(at: point, in: view) {
                UIApplication.shared.open(url)
                return
            }
            guard let edit = taskEdit(at: point, in: view) else { return }
            let selection = view.selectedRange
            parent.controller.apply(edit)
            view.selectedRange = selection
        }

        /// Тап забирается у редактора только по квадратику или ссылке — остальное как обычно.
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let view = gesture.view as? UITextView else { return false }
            let point = gesture.location(in: view)
            return taskEdit(at: point, in: view) != nil || link(at: point, in: view) != nil
        }

        /// Ссылка под пальцем: символ с адресом, и палец действительно на его глифе.
        private func link(at point: CGPoint, in view: UITextView) -> URL? {
            let layout = view.layoutManager
            let local = CGPoint(x: point.x - view.textContainerInset.left, y: point.y - view.textContainerInset.top)
            var fraction: CGFloat = 0
            let index = layout.characterIndex(for: local, in: view.textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)
            guard index < view.textStorage.length,
                  let url = view.textStorage.attribute(LiveMarkdownStyler.linkKey, at: index, effectiveRange: nil) as? URL else { return nil }
            let glyph = layout.glyphIndexForCharacter(at: index)
            let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: view.textContainer)
            return rect.insetBy(dx: -4, dy: -6).contains(local) ? url : nil
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }

        private func taskEdit(at point: CGPoint, in view: UITextView) -> MarkdownFormatting.Edit? {
            guard let layout = view.layoutManager as? LiveLayoutManager else { return nil }
            let origin = CGPoint(x: view.textContainerInset.left, y: view.textContainerInset.top)
            return layout.taskToggle(at: point, origin: origin)
        }
    }
}

/// Курсор высотой со шрифт строки: UIKit тянул его на всю строку вместе с полями
/// абзаца — у первой и последней строки цитаты он выходил огромным.
final class MarkdownUITextView: UITextView {
    override func caretRect(for position: UITextPosition) -> CGRect {
        let rect = super.caretRect(for: position)
        let length = textStorage.length
        let index = offset(from: beginningOfDocument, to: position)
        let ns = textStorage.string as NSString
        // В конце текста после перевода строки — пустая «лишняя» строка, у неё свой расчёт.
        guard length > 0, !(index >= length && ns.character(at: length - 1) == 0x0A) else { return rect }
        let char = min(index, length - 1)
        let font = textStorage.attribute(.font, at: char, effectiveRange: nil) as? UIFont ?? LiveMarkdownStyler.font
        let glyph = layoutManager.glyphIndexForCharacter(at: char)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = textContainerInset.top + line.minY + layoutManager.location(forGlyphAt: glyph).y
        return CGRect(x: rect.minX, y: baseline - font.ascender, width: rect.width, height: font.ascender - font.descender)
    }
}

/// Команды панели Markdown и состояние для неё: выделение, активные стили.
@Observable
final class MarkdownEditorController {
    @ObservationIgnored weak var textView: UITextView?
    @ObservationIgnored weak var coordinator: MarkdownTextView.Coordinator?
    /// Пустая пара `****` от кнопки без выделения — скрыта, пока в неё не начали печатать.
    @ObservationIgnored var pendingPair: NSRange?

    private(set) var selection = NSRange(location: 0, length: 0)
    private(set) var activeInlines: Set<String> = []
    private(set) var activeBlock: String?

    var hasSelection: Bool { selection.length > 0 }

    // MARK: Состояние

    func update(selection: NSRange, text: String, paragraphs: [MarkdownStyler.Paragraph]) {
        if self.selection != selection { self.selection = selection }
        if let pending = pendingPair, !NSLocationInRange(selection.location, NSRange(location: pending.location, length: pending.length + 1)) {
            // Ушли из пустой пары, так ничего и не напечатав, — убрать её.
            pendingPair = nil
            if (text as NSString).length >= NSMaxRange(pending) {
                DispatchQueue.main.async { [weak self] in
                    self?.apply(.init(range: pending, replacement: "", selection: self?.textView?.selectedRange ?? selection), keepSelection: true)
                }
            }
        }
        let location = selection.location
        guard let line = paragraphs.first(where: { $0.range.location <= location && location <= NSMaxRange($0.range) }) else {
            activeInlines = []; activeBlock = nil; return
        }
        var inlines: Set<String> = []
        for (range, style) in line.inlines where range.location < max(location, NSMaxRange(selection)) && location <= NSMaxRange(range) {
            switch style {
            case .bold: inlines.insert("**")
            case .italic: inlines.insert("*")
            case .strikethrough: inlines.insert("~~")
            case .underline: inlines.insert("~")
            case .highlight: inlines.insert("==")
            case .code: inlines.insert("`")
            case .link: inlines.insert("link")
            }
        }
        if inlines != activeInlines { activeInlines = inlines }
        let block: String? = switch line.block {
        case .heading: "# "
        case .bullet: "- "
        case .task: "- [ ] "
        case .quote: "> "
        case .numbered: "1. "
        case .code, .codeFence: "```"
        default: nil
        }
        if block != activeBlock { activeBlock = block }
    }

    /// Набрали текст в пустую пару — она стала обычным фрагментом.
    func textDidChange(_ text: String) {
        guard let pending = pendingPair else { return }
        let ns = text as NSString
        if NSMaxRange(pending) > ns.length || ns.substring(with: pending).count != pending.length
            || !ns.substring(with: pending).allSatisfy({ "*~=`".contains($0) }) {
            pendingPair = nil
        }
    }

    // MARK: Правки

    /// Правка через UITextInput — с undo и обычными уведомлениями редактора.
    func apply(_ edit: MarkdownFormatting.Edit, keepSelection: Bool = false) {
        guard let view = textView,
              let start = view.position(from: view.beginningOfDocument, offset: edit.range.location),
              let end = view.position(from: start, offset: edit.range.length),
              let range = view.textRange(from: start, to: end) else { return }
        coordinator?.isApplying = true
        view.replace(range, withText: edit.replacement)
        coordinator?.isApplying = false
        let length = (view.text as NSString).length
        let selection = keepSelection ? view.selectedRange : edit.selection
        view.selectedRange = NSRange(location: min(selection.location, length), length: min(selection.length, max(0, length - selection.location)))
        coordinator?.textViewDidChange(view)
    }

    private var text: NSString { (textView?.text ?? "") as NSString }

    /// Жирный, курсив и т.п. Без выделения: слово под курсором; вне слова —
    /// пустая скрытая пара, печать продолжается уже оформленной.
    func wrap(_ marker: String) {
        var selection = textView?.selectedRange ?? self.selection
        if selection.length == 0, let word = word(at: selection.location) { selection = word }
        let edit = MarkdownFormatting.toggle(marker, in: text, selection: selection)
        apply(edit)
        if selection.length == 0, edit.replacement == marker + marker {
            pendingPair = NSRange(location: edit.range.location, length: (edit.replacement as NSString).length)
            if let view = textView { coordinator?.restyle(view) }
        }
    }

    /// Маркер блока в начале строки: тот же — снять, другой — заменить.
    func block(_ marker: String) {
        let selection = textView?.selectedRange ?? self.selection
        let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = MarkdownStyler.paragraph(in: text, lineRange: lineRange)
        var existing: NSRange?
        switch line.block {
        case .heading, .bullet, .task, .quote: existing = line.blockMarker
        case .numbered:
            // Номер не скрыт и не маркер в разборе — но для панели это маркер строки.
            let lineText = text.substring(with: line.range)
            if let match = lineText.range(of: #"^\d+\. "#, options: .regularExpression) {
                existing = NSRange(location: line.range.location, length: (String(lineText[match]) as NSString).length)
            }
        default: break
        }
        let current = existing.map { text.substring(with: $0) }
        let same = current.map { $0 == marker || (marker == "- [ ] " && $0.hasPrefix("- ["))
            || (marker == "1. " && $0.range(of: #"^\d+\. $"#, options: .regularExpression) != nil) } ?? false
        let range = existing ?? NSRange(location: lineRange.location, length: 0)
        let replacement = same ? "" : marker
        let shift = (replacement as NSString).length - range.length
        apply(.init(range: range, replacement: replacement,
                    selection: NSRange(location: max(lineRange.location, selection.location + shift), length: selection.length)))
    }

    func codeBlock() {
        let selection = textView?.selectedRange ?? self.selection
        apply(MarkdownFormatting.toggleCodeBlock(in: text, selection: selection))
    }

    /// Выделенный текст (или `title`) — ссылкой на `url`.
    func insertLink(title: String, url: String) {
        let selection = textView?.selectedRange ?? self.selection
        let label = selection.length > 0 ? text.substring(with: selection) : title
        var address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.contains("://") { address = "https://" + address }
        let link = "[\(label.isEmpty ? address : label)](\(address))"
        apply(.init(range: selection, replacement: link,
                    selection: NSRange(location: selection.location + (link as NSString).length, length: 0)))
    }

    func selectedText() -> String {
        let selection = textView?.selectedRange ?? self.selection
        guard selection.length > 0, NSMaxRange(selection) <= text.length else { return "" }
        return text.substring(with: selection)
    }

    /// Слово, внутри которого курсор (не на его краю).
    private func word(at location: Int) -> NSRange? {
        let ns = text
        func isWordChar(_ i: Int) -> Bool {
            guard i >= 0, i < ns.length, let scalar = Unicode.Scalar(ns.character(at: i)) else { return false }
            return CharacterSet.alphanumerics.contains(scalar)
        }
        guard isWordChar(location - 1), isWordChar(location) else { return nil }
        var start = location, end = location
        while isWordChar(start - 1) { start -= 1 }
        while isWordChar(end) { end += 1 }
        return NSRange(location: start, length: end - start)
    }
}
