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
    static let dividerLineColor = NSColor.labelColor.withAlphaComponent(0.22)

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

    /// Единая точка, через которую AppKit проводит ЛЮБОЕ изменение
    /// выделения — мышью (клик, drag), клавиатурой (стрелки, Shift+стрелки,
    /// Cmd+←), программно. В отличие от doCommandBy (который ловит только
    /// именованные клавиатурные команды и не видит мышь вообще), это
    /// гарантированно перехватывает абсолютно все пути — поэтому именно здесь
    /// не даём выделению/курсору заходить ДО конца маркера списка.
    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRange(Self.clampSelectionRange(charRange, in: self), affinity: affinity, stillSelecting: stillSelectingFlag)
    }

    /// NSTextView по умолчанию регистрирует I-beam на весь свой bounds
    /// БЕЗ учёта фокуса — это перекрывает точечные NSCursor.set() вызовы у
    /// крестика/тега/resize-хендла карточки (у них нет собственных cursor
    /// rect, только у поля текста), из-за чего I-beam виден вообще везде,
    /// даже когда карточка не в фокусе. Пока карточка не активна — вся
    /// область показывает обычную стрелку; I-beam появляется только когда
    /// текстовое поле реально стало first responder.
    override func resetCursorRects() {
        let cursor: NSCursor = (window?.firstResponder === self) ? .iBeam : .arrow
        addCursorRect(bounds, cursor: cursor)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        window?.invalidateCursorRects(for: self)
        return result
    }

    /// resetCursorRects одного не хватает: в современном AppKit NSTextView
    /// также навязывает I-beam императивно через mouseMoved (не только через
    /// классическую cursor-rect таблицу), поэтому пока карточка не в фокусе,
    /// не даём super вообще увидеть это событие — принудительно ставим
    /// стрелку сами. В фокусе — обычное поведение NSTextView (I-beam).
    override func mouseMoved(with event: NSEvent) {
        guard window?.firstResponder === self else {
            NSCursor.arrow.set()
            return
        }
        super.mouseMoved(with: event)
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        window?.invalidateCursorRects(for: self)
        return result
    }

    private static func clampSelectionRange(_ range: NSRange, in textView: NSTextView) -> NSRange {
        guard let textStorage = textView.textStorage, textStorage.length > 0 else { return range }
        let ns = textStorage.string as NSString

        func clamp(_ location: Int) -> Int {
            guard location >= 0, location <= ns.length, ns.length > 0 else { return location }
            let probeLocation = min(location, ns.length - 1)
            var lineRange = ns.paragraphRange(for: NSRange(location: probeLocation, length: 0))
            if lineRange.length > 0,
               ns.substring(with: NSRange(location: lineRange.location + lineRange.length - 1, length: 1)) == "\n" {
                lineRange.length -= 1
            }
            guard let prefix = detectListPrefix(in: ns, lineRange: lineRange) else { return location }
            let contentStart = lineRange.location + prefix.length
            // >= (не >): позиция РОВНО на первом символе маркера тоже должна
            // поджиматься к концу маркера — иначе Cmd+←/Home всё ещё могли
            // поставить курсор перед самим значком.
            guard location >= lineRange.location, location < contentStart else { return location }
            return contentStart
        }

        let start = clamp(range.location)
        let end = clamp(range.location + range.length)
        let newStart = min(start, end)
        let newEnd = max(start, end)
        return NSRange(location: newStart, length: newEnd - newStart)
    }

    /// Маркер списка, обнаруженный в начале строки.
    enum ListPrefix {
        case bullet
        case numbered(Int)

        var length: Int {
            switch self {
            case .bullet: return 2 // "• "
            case .numbered(let n): return "\(n). ".count
            }
        }

        /// Аттрибутированная строка нового маркера продолжения списка
        /// (без ведущего "\n" — его добавляет вызывающий код).
        func attributedMarker(baseAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
            switch self {
            case .bullet:
                return NSAttributedString(string: "• ", attributes: baseAttributes)
            case .numbered(let n):
                return NSAttributedString(string: "\(n + 1). ", attributes: baseAttributes)
            }
        }
    }

    /// "• " -> маркированный список, "1. "/"12. " и т.п. -> нумерованный.
    /// Отдельной "активации" для чисел не нужно — "1. " уже выглядит как
    /// корректный маркер, распознаётся здесь же в момент нажатия Enter.
    static func detectListPrefix(in ns: NSString, lineRange: NSRange) -> ListPrefix? {
        guard lineRange.length >= 2 else { return nil }
        let line = ns.substring(with: lineRange)

        if line.hasPrefix("• ") {
            return .bullet
        }

        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }

        let rest = line[line.index(line.startIndex, offsetBy: digits.count)...]
        guard rest.hasPrefix(". ") else { return nil }

        return .numbered(number)
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
    /// Единственный источник горизонтального инсета текста — раньше
    /// updateNSView независимо считал ширину как "cardSize.width - 40",
    /// не привязывая это число к textContainerInset ниже; расхождение
    /// пришлось бы чинить в двух местах при изменении отступа.
    private static let horizontalTextInset: CGFloat = 20

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
        textView.textContainerInset = NSSize(width: Self.horizontalTextInset, height: 20)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textColor = NSColor.labelColor.withAlphaComponent(0.88)
        textView.typingAttributes = Self.baseAttributes()

        textView.textStorage?.setAttributedString(Self.buildAttributedString(from: text))

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CardNSTextView else { return }

        let innerWidth = max(cardSize.width - Self.horizontalTextInset * 2, 10)
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
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.88),
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

        /// Стандартный хук NSTextViewDelegate для перехвата команд редактирования
        /// (Enter, Tab и т.п.) до их выполнения по умолчанию — то, как в Cocoa
        /// принято реализовывать "умный" Enter для списков, а не постфактум
        /// разбирать текст в textDidChange.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return continueListIfNeeded(in: textView)
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                return removeMarkerOnBackspaceIfNeeded(in: textView)
            }
            if commandSelector == #selector(NSResponder.moveLeft(_:)) {
                return jumpOverMarkerOnMoveLeftIfNeeded(in: textView)
            }
            return false
        }

        /// Обычная ← ровно на границе маркера (курсор уже стоит сразу после
        /// него) перепрыгивает в конец предыдущей строки вместо захода
        /// "внутрь" маркера. `moveToBeginningOfLine:` (Cmd+←) и вообще любое
        /// выделение отдельно не перехватываются здесь — их без исключений
        /// покрывает CardNSTextView.setSelectedRange(_:affinity:stillSelecting:),
        /// куда в итоге стекается любое изменение selection независимо от
        /// источника (клавиатура, мышь, drag) — просто не даёт встать раньше
        /// конца маркера, без специального "прыжка".
        private func jumpOverMarkerOnMoveLeftIfNeeded(in textView: NSTextView) -> Bool {
            let cursor = textView.selectedRange()
            guard cursor.length == 0 else { return false }

            let ns = textView.string as NSString
            var lineRange = ns.paragraphRange(for: NSRange(location: cursor.location, length: 0))
            if lineRange.length > 0,
               ns.substring(with: NSRange(location: lineRange.location + lineRange.length - 1, length: 1)) == "\n" {
                lineRange.length -= 1
            }

            guard let prefix = CardNSTextView.detectListPrefix(in: ns, lineRange: lineRange) else { return false }
            let contentStart = lineRange.location + prefix.length
            guard cursor.location == contentStart else { return false }

            let previousLineEnd = max(0, lineRange.location - 1)
            textView.setSelectedRange(NSRange(location: previousLineEnd, length: 0))
            return true
        }

        /// Backspace сразу после маркера убирает маркер целиком одним
        /// нажатием — симметрично с Enter на пустом пункте, и не даёт
        /// курсору "провалиться" внутрь маркера (между значком и пробелом),
        /// как это было бы при обычном посимвольном удалении. Если после
        /// маркера ещё есть текст — строка становится обычной (маркер снят),
        /// как в стандартных списках Notes/Word; если пусто — исчезает вся
        /// строка целиком.
        private func removeMarkerOnBackspaceIfNeeded(in textView: NSTextView) -> Bool {
            let cursor = textView.selectedRange()
            guard cursor.length == 0, cursor.location > 0 else { return false }

            let ns = textView.string as NSString
            var lineRange = ns.paragraphRange(for: NSRange(location: cursor.location, length: 0))
            if lineRange.length > 0,
               ns.substring(with: NSRange(location: lineRange.location + lineRange.length - 1, length: 1)) == "\n" {
                lineRange.length -= 1
            }

            guard let prefix = CardNSTextView.detectListPrefix(in: ns, lineRange: lineRange) else { return false }
            // Курсор должен стоять ровно сразу после маркера — иначе это
            // обычный backspace где-то в тексте пункта, не наша забота.
            guard cursor.location == lineRange.location + prefix.length else { return false }

            textView.textStorage?.beginEditing()
            textView.textStorage?.replaceCharacters(in: NSRange(location: lineRange.location, length: prefix.length), with: "")
            textView.textStorage?.endEditing()

            let affectedRange = NSRange(location: lineRange.location, length: max(0, (textView.string as NSString).length - lineRange.location))
            textView.layoutManager?.invalidateLayout(forCharacterRange: affectedRange, actualCharacterRange: nil)
            textView.layoutManager?.ensureLayout(forCharacterRange: affectedRange)
            textView.needsDisplay = true

            textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
            textView.didChangeText()

            return true
        }

        /// Требование: Enter на непустом пункте списка ("• текст" или "N. текст")
        /// продолжает список новым маркером на следующей строке; Enter на
        /// пустом пункте ("• "/"N. " без текста) убирает маркер вместо
        /// переноса строки — как в стандартных списках Notes/TextEdit.
        private func continueListIfNeeded(in textView: NSTextView) -> Bool {
            let cursor = textView.selectedRange()
            guard cursor.length == 0 else { return false }

            let ns = textView.string as NSString
            var lineRange = ns.paragraphRange(for: NSRange(location: cursor.location, length: 0))
            if lineRange.length > 0,
               ns.substring(with: NSRange(location: lineRange.location + lineRange.length - 1, length: 1)) == "\n" {
                lineRange.length -= 1
            }

            guard let prefix = CardNSTextView.detectListPrefix(in: ns, lineRange: lineRange) else { return false }

            let contentRange = NSRange(location: lineRange.location + prefix.length, length: lineRange.length - prefix.length)
            let hasContent = contentRange.length > 0
                && !ns.substring(with: contentRange).trimmingCharacters(in: .whitespaces).isEmpty

            let newCursorLocation: Int
            textView.textStorage?.beginEditing()
            if hasContent {
                let base = CardTextView.baseAttributes()
                let insertion = NSMutableAttributedString(string: "\n", attributes: base)
                insertion.append(prefix.attributedMarker(baseAttributes: base))
                textView.textStorage?.replaceCharacters(in: cursor, with: insertion)
                newCursorLocation = cursor.location + insertion.length
            } else {
                textView.textStorage?.replaceCharacters(in: lineRange, with: "")
                newCursorLocation = lineRange.location
            }
            textView.textStorage?.endEditing()

            // Без явной инвалидации TextKit мог рисовать по ещё не
            // пересчитанному layout сразу после правки — маркер либо
            // оставался "приклеенным" к предыдущей строке, либо для удаления
            // пустого пункта требовалось нажать Enter дважды (первый раз
            // просто ничего не перерисовывал).
            let affectedRange = NSRange(location: lineRange.location, length: max(0, (textView.string as NSString).length - lineRange.location))
            textView.layoutManager?.invalidateLayout(forCharacterRange: affectedRange, actualCharacterRange: nil)
            textView.layoutManager?.ensureLayout(forCharacterRange: affectedRange)
            textView.needsDisplay = true

            // setSelectedRange — только ПОСЛЕ endEditing(): пока транзакция
            // редактирования textStorage не закрыта, layout ещё не
            // пересчитан, и попытка выставить selection в этот момент уводит
            // NSTextView в зависшее состояние (переставали работать Enter,
            // ввод, выделение, удаление — вплоть до потери фокуса).
            textView.setSelectedRange(NSRange(location: newCursorLocation, length: 0))

            // Прямая правка textStorage (replaceCharacters) не уведомляет
            // делегата сама по себе — didChangeText() обязателен, иначе
            // card.text не синхронизируется с этим изменением, и следующий
            // ререндер (updateNSView увидит рассинхрон) затирает только что
            // вставленную строку старым значением card.text.
            textView.didChangeText()

            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            applyTypingAttributes(to: textView)
            replaceDashLineWithDividerIfNeeded(in: textView)
            replaceDashPrefixWithBulletIfNeeded(in: textView)

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
            // См. комментарий в continueListIfNeeded — обязателен после
            // прямой правки textStorage, иначе card.text не подхватит вставку.
            textView.didChangeText()
        }

        // "- " в начале строки -> "• " (стандартный маркер списка).
        private func replaceDashPrefixWithBulletIfNeeded(in textView: NSTextView) {
            let selectedLocation = textView.selectedRange().location
            guard selectedLocation > 0 else { return }

            let ns = textView.string as NSString
            guard selectedLocation <= ns.length,
                  ns.substring(with: NSRange(location: selectedLocation - 1, length: 1)) == " "
            else { return }

            let paragraphRange = ns.paragraphRange(for: NSRange(location: selectedLocation, length: 0))
            let prefixRange = NSRange(location: paragraphRange.location, length: selectedLocation - paragraphRange.location)
            guard prefixRange.length == 2, ns.substring(with: prefixRange) == "- " else { return }

            let bulletString = NSAttributedString(string: "•", attributes: CardTextView.baseAttributes())

            textView.textStorage?.beginEditing()
            textView.textStorage?.replaceCharacters(in: NSRange(location: prefixRange.location, length: 1), with: bulletString)
            textView.textStorage?.endEditing()

            // Замена того же размера (1 символ на 1 символ) — позиция курсора
            // не сдвигается, но выставляем явно на случай, если TextKit
            // сбросит selection при replaceCharacters.
            textView.setSelectedRange(NSRange(location: selectedLocation, length: 0))
            // См. комментарий в continueListIfNeeded — обязателен после
            // прямой правки textStorage, иначе card.text не подхватит вставку.
            textView.didChangeText()
        }
    }
}
