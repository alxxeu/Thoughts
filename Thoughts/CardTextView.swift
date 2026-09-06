import SwiftUI
import AppKit

// MARK: - Divider Attachment

/// Маркер разделителя в тексте. Сам по себе ничего не рисует и не занимает
/// заметного места — реальная линия рисуется отдельно, поверх обычного
/// прохода отрисовки, в `CardNSTextView.draw(_:)`. Такой подход (вместо
/// кастомных `image(forBounds:)`/`NSTextAttachmentCell`) полностью убирает
/// рассинхрон между тем, что TextKit насчитал для layout, и тем, что
/// реально попадает на экран — здесь позиция строки берётся из ЖИВОГО
/// `layoutManager` в момент самой отрисовки, каждый раз заново.
final class DividerAttachment: NSTextAttachment {
    /// Высота строки, которую резервирует под себя разделитель в тексте —
    /// заметно больше обычной строки (15pt шрифт + 4pt lineSpacing ≈ 22pt),
    /// чтобы всегда был чёткий зазор до соседних строк сверху и снизу.
    static let rowHeight: CGFloat = 30

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        // Минимальная невидимая "заглушка" (не 0 — вырожденный по площади
        // rect некоторые внутренности TextKit могут обработать как особый
        // случай и пропустить генерацию глифа). Реальная ширина линии не
        // нужна здесь, она вычисляется отдельно в CardNSTextView.draw(_:).
        NSRect(x: 0, y: 0, width: 1, height: Self.rowHeight)
    }

    override func image(forBounds imageBounds: NSRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> NSImage? {
        nil
    }
}

// MARK: - Custom NSTextView (plain-text paste + divider drawing)

private final class CardNSTextView: NSTextView {
    static let dividerLineColor = NSColor.white.withAlphaComponent(0.22)

    // Требование 4: вставка всегда plain text в стиле карточки.
    // Работает только с диапазоном вставки — существующие NSTextAttachment
    // (наши разделители) в остальном тексте не затрагиваются.
    //
    // Принципиально не вызываем super.paste(sender) здесь: если в буфере нет
    // строки, super попытался бы материализовать содержимое под остальные
    // читаемые типы (включая изображения), а для "promise"-данных (например,
    // скопированных из Chrome или Photos) это заметно подвисает — системе
    // приходится реально скачать/сконвертировать картинку только ради
    // проверки формата. Просто ничего не делаем — вставки не происходит.
    override func paste(_ sender: Any?) {
        guard let plain = NSPasteboard.general.string(forType: .string) else { return }
        insertText(plain, replacementRange: selectedRange())
    }

    /// Рисует линии разделителей поверх обычного текста. Проходит по всем
    /// диапазонам с атрибутом `.attachment` типа `DividerAttachment` и для
    /// каждого берёт СВЕЖИЙ line fragment rect у layoutManager — то есть
    /// позиция всегда соответствует текущему, только что посчитанному layout,
    /// без риска отрисовать линию по устаревшим/закэшированным координатам.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let layoutManager, let textContainer, let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let origin = textContainerOrigin

        textStorage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard value is DividerAttachment else { return }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let y = (origin.y + lineRect.midY).rounded()

            let path = NSBezierPath()
            path.move(to: NSPoint(x: origin.x, y: y))
            path.line(to: NSPoint(x: origin.x + textContainer.size.width, y: y))
            path.lineWidth = 1
            Self.dividerLineColor.setStroke()
            path.stroke()
        }
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
        // Изображения не поддерживаются: выключенный импорт графики не даёт
        // картинке попасть в текст через paste или drag-and-drop.
        textView.importsGraphics = false
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
                result.append(Self.dividerAttributedString(with: base))
            } else {
                result.append(NSAttributedString(string: String(character), attributes: base))
            }
        }

        return result
    }

    /// Attachment-строка с теми же атрибутами (в т.ч. `lineSpacing` в
    /// paragraphStyle), что у обычного текста — иначе параграф разделителя
    /// получает другую метрику строки, чем соседний текст, и высота
    /// `attachmentBounds` перестаёт совпадать с реальным зазором до
    /// следующей строки (она "налезает" сверху).
    fileprivate static func dividerAttributedString(with baseAttributes: [NSAttributedString.Key: Any] = baseAttributes()) -> NSAttributedString {
        let attachmentString = NSMutableAttributedString(attachment: DividerAttachment())
        attachmentString.addAttributes(baseAttributes, range: NSRange(location: 0, length: attachmentString.length))
        return attachmentString
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

            let attachmentString = CardTextView.dividerAttributedString()

            textView.textStorage?.beginEditing()
            textView.textStorage?.replaceCharacters(in: paragraphRange, with: attachmentString)
            textView.textStorage?.endEditing()

            // Без явной инвалидации TextKit может не пересчитать
            // attachmentBounds/не перерисовать линию сразу — она появлялась
            // только после следующего внешнего relayout (например, ресайза
            // карточки). Форсируем layout и отрисовку строки с разделителем
            // немедленно после вставки.
            let insertedRange = NSRange(location: paragraphRange.location, length: attachmentString.length)
            textView.layoutManager?.invalidateLayout(forCharacterRange: insertedRange, actualCharacterRange: nil)
            textView.layoutManager?.ensureLayout(forCharacterRange: insertedRange)
            textView.needsDisplay = true

            // +1 за attachment и ещё +1 за оставшийся "\n" сразу после него
            // (paragraphRange не включает этот "\n", он не был заменён) —
            // курсор должен встать уже В СЛЕДУЮЩЕМ параграфе. Раньше он
            // вставал МЕЖДУ attachment-ом и этим "\n", из-за чего весь текст,
            // напечатанный сразу после, попадал в один параграф с
            // разделителем — визуально линия и следующая строка сливались.
            let newLocation = min(paragraphRange.location + attachmentString.length + 1, (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))
        }
    }
}
