import SwiftUI
import AppKit

// MARK: - Divider Attachment

/// Векторный разделитель. Ширина не фиксируется при создании — она
/// пересчитывается NSTextView на каждый layout pass через attachmentBounds(for:...),
/// беря актуальную ширину textContainer, поэтому линия всегда растягивается
/// на всю ширину карточки, включая изменение размера в реальном времени.
final class DividerAttachment: NSTextAttachment {
    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        let width = textContainer?.size.width ?? lineFrag.width
        return NSRect(x: 0, y: -4, width: max(width, 1), height: 16)
    }

    override func image(
        forBounds imageBounds: NSRect,
        textContainer: NSTextContainer?,
        characterIndex charIndex: Int
    ) -> NSImage? {
        let size = imageBounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        let image = NSImage(size: size)
        image.lockFocus()
        let path = NSBezierPath()
        let y = size.height / 2
        path.move(to: NSPoint(x: 0, y: y))
        path.line(to: NSPoint(x: size.width, y: y))
        path.lineWidth = 1
        NSColor.white.withAlphaComponent(0.12).setStroke()
        path.stroke()
        image.unlockFocus()

        return image
    }
}

// MARK: - Custom NSTextView (plain-text paste)

private final class CardNSTextView: NSTextView {
    // Требование 4: вставка всегда plain text в стиле карточки.
    // Работает только с диапазоном вставки — существующие NSTextAttachment
    // (наши разделители) в остальном тексте не затрагиваются.
    override func paste(_ sender: Any?) {
        guard let plain = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }
        insertText(plain, replacementRange: selectedRange())
    }
}

// MARK: - CardTextView

struct CardTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var cardSize: CGSize
    var onTextChange: () -> Void
    var onFocusChange: (Bool) -> Void

    private static let dividerPlaceholder: Character = "\u{FFFC}"

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = CardNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsUndo = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        if #available(macOS 14.0, *) {
                   textView.inlinePredictionType = .no
               }
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textColor = NSColor.white.withAlphaComponent(0.88)
        textView.typingAttributes = Self.baseAttributes()

        textView.textStorage?.setAttributedString(Self.buildAttributedString(from: text))

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CardNSTextView else { return }

        let innerWidth = max(cardSize.width - 40, 10)
        if let container = textView.textContainer,
           abs(container.size.width - innerWidth) > 0.5 {
            container.size = NSSize(width: innerWidth, height: .greatestFiniteMagnitude)
            textView.layoutManager?.invalidateLayout(
                forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length),
                actualCharacterRange: nil
            )
        }

        // Требование 6: обновляем содержимое NSTextView только если оно
        // реально разошлось с привязкой — иначе получаем бесконечный цикл
        // (textDidChange -> $text = ... -> updateNSView -> setAttributedString -> ...).
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            let attributed = Self.buildAttributedString(from: text)
            textView.textStorage?.setAttributedString(attributed)
            textView.selectedRanges = selectedRanges
        }

        // Синхронный переход фокуса, срабатывающий только один раз на реальное
        // изменение состояния — иначе makeFirstResponder на уже сфокусированном
        // NSTextView на каждый keystroke рвёт активную input-сессию AppKit.
        if isFocused {
            if !context.coordinator.didRequestFocus {
                context.coordinator.didRequestFocus = true
                if nsView.window?.firstResponder !== textView {
                    nsView.window?.makeFirstResponder(textView)
                }
            }
        } else {
            if context.coordinator.didRequestFocus {
                context.coordinator.didRequestFocus = false
                if nsView.window?.firstResponder === textView {
                    textView.setSelectedRange(NSRange(location: 0, length: 0))
                    nsView.window?.makeFirstResponder(nil)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Attributed string helpers

    fileprivate static func baseAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        return [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.white.withAlphaComponent(0.88),
            .paragraphStyle: paragraph
        ]
    }

    /// U+FFFC в исходной String — это ровно то место, куда NSTextView сам
    /// подставляет символ attachment-а в свою plain-string репрезентацию.
    /// Поскольку в карточке используется только один тип attachment (разделитель),
    /// каждое такое вхождение детерминированно восстанавливается обратно
    /// без необходимости хранить AttributedString отдельно.
    fileprivate static func buildAttributedString(from text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let base = baseAttributes()

        for character in text {
            if character == dividerPlaceholder {
                result.append(NSAttributedString(attachment: DividerAttachment()))
            } else {
                result.append(NSAttributedString(string: String(character), attributes: base))
            }
        }

        return result
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CardTextView
        var didRequestFocus = false

        init(_ parent: CardTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            applyTypingAttributes(to: textView)
            replaceDashLineWithDividerIfNeeded(in: textView)

            parent.text = textView.string
            parent.onTextChange()
        }

        func textDidBeginEditing(_ notification: Notification) {
            DispatchQueue.main.async {
                self.parent.isFocused = true
                self.parent.onFocusChange(true)
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            }
            DispatchQueue.main.async {
                self.parent.isFocused = false
                self.parent.onFocusChange(false)
            }
        }

        // Гарантирует, что вновь введённый текст остаётся в базовом стиле
        // карточки (15pt, line spacing 4), даже если курсор стоит сразу
        // после разделителя-attachment.
        private func applyTypingAttributes(to textView: NSTextView) {
            textView.typingAttributes = CardTextView.baseAttributes()
        }

        // Требование 3: строка из 3-20 тире, завершённая переносом строки, -> векторный разделитель.
        private func replaceDashLineWithDividerIfNeeded(in textView: NSTextView) {
            let selectedLocation = textView.selectedRange().location
            guard selectedLocation > 0 else { return }

            let ns = textView.string as NSString
            guard selectedLocation <= ns.length,
                  ns.substring(with: NSRange(location: selectedLocation - 1, length: 1)) == "\n"
            else { return }

            var paragraphRange = ns.paragraphRange(
                for: NSRange(location: max(0, selectedLocation - 2), length: 0)
            )
            if paragraphRange.length > 0,
               ns.substring(with: NSRange(location: paragraphRange.location + paragraphRange.length - 1, length: 1)) == "\n" {
                paragraphRange.length -= 1
            }

            guard paragraphRange.length >= 3, paragraphRange.length <= 20 else { return }

            let lineText = ns.substring(with: paragraphRange)
            guard lineText.allSatisfy({ $0 == "-" }) else { return }

            let attachmentString = NSAttributedString(attachment: DividerAttachment())

            textView.textStorage?.beginEditing()
            textView.textStorage?.replaceCharacters(in: paragraphRange, with: attachmentString)
            textView.textStorage?.endEditing()

            let newLocation = min(paragraphRange.location + 1, (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))
        }
    }
}
