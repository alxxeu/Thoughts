import SwiftUI
import AppKit

// MARK: - Custom NSTextView (вставка как текст, списки, фокус; рисование — MarkdownBlockDecorator)

private final class CardNSTextView: NSTextView {
    // Источник истины для фокуса наружу, в SwiftUI. NSTextViewDelegate's
    // textDidBeginEditing/textDidEndEditing здесь на практике не
    // срабатывают на обычный клик (похоже, из-за override'ов ниже,
    // управляющих курсором в обход стандартной editing-сессии) — а вот
    // become/resignFirstResponder вызываются гарантированно, на них и
    // держится I-beam-курсор чуть ниже, так что это единственный
    // надёжный сигнал смены фокуса.
    var onFirstResponderChange: ((Bool) -> Void)?
    /// Непустой только когда карточка в Focus Mode — см. cancelOperation ниже.
    var onEscape: (() -> Void)?
    /// Места, где курсору нельзя стоять (внутри скрытых символов Markdown) —
    /// обновляет restyle; между правкой и перекраской пустые.
    var atoms: [LiveMarkdown.Atom] = []

    // Производный от цвета текста (Settings → Appearance), а не
    // адаптивный labelColor — фон карточки (CardSurfaceStyle) не
    // переключается в светлый в Light Mode, так что линии поверх него
    // должны следовать за текстом, а не за темой.
    var dividerLineColor = CardTypography.defaultTextColor.withAlphaComponent(0.22)
    /// Ширина — всегда ровно по видимой области прокрутки: карточка
    /// прокручивается только вертикально. Без этого после анимации появления
    /// AI-карточки (масштаб 0.35 → 1) текст оставался шире карточки, и её
    /// можно было сдвинуть вбок.
    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        if let visible = enclosingScrollView?.contentSize.width, visible > 0 {
            size.width = visible
        }
        super.setFrameSize(size)
    }

    /// Делегат вёрстки, рисующий `-` списка как `•`. layoutManager
    /// держит делегата слабо — храним здесь.
    let bulletGlyphs = MarkdownBulletGlyphs()

    // Вставка — всегда текст как есть: Markdown из Notion, сайтов и
    // md-приложений сразу отрисуется, а чужое форматирование (RTF/HTML)
    // в карточку не попадает.
    //
    // Принципиально не вызываем super.paste(sender) здесь: если в буфере нет
    // строки, super попытался бы материализовать содержимое под остальные
    // читаемые типы (включая изображения), а для "promise"-данных (например,
    // скопированных из Chrome или Photos) это заметно подвисает — системе
    // приходится реально скачать/сконвертировать картинку только ради
    // проверки формата. Просто ничего не делаем — вставки не происходит.
    override func paste(_ sender: Any?) {
        guard let plain = NSPasteboard.general.string(forType: .string) else { return }
        let range = selectedRange()
        let atLineStart = range.location == 0 || (string as NSString).character(at: range.location - 1) == 0x0A
        insertText(MarkdownFormatting.standardizingTaskMarkers(plain, atLineStart: atLineStart), replacementRange: range)
    }

    // MARK: Format (⌘B, ⌘I, …) — меню шлёт эти действия по responder chain

    @objc func markdownBold(_ sender: Any?) { toggleMarkdown("**") }
    @objc func markdownItalic(_ sender: Any?) { toggleMarkdown("*") }
    @objc func markdownUnderline(_ sender: Any?) { toggleMarkdown("~") }
    @objc func markdownStrikethrough(_ sender: Any?) { toggleMarkdown("~~") }
    @objc func markdownHighlight(_ sender: Any?) { toggleMarkdown("==") }

    @objc func markdownCode(_ sender: Any?) { toggleMarkdown("`") }
    @objc func markdownHeading1(_ sender: Any?) { toggleBlock(.heading(1)) }
    @objc func markdownHeading2(_ sender: Any?) { toggleBlock(.heading(2)) }
    @objc func markdownHeading3(_ sender: Any?) { toggleBlock(.heading(3)) }
    @objc func markdownBulletList(_ sender: Any?) { toggleBlock(.bullet) }
    @objc func markdownNumberedList(_ sender: Any?) { toggleBlock(.numbered) }
    @objc func markdownTask(_ sender: Any?) { toggleBlock(.task) }
    @objc func markdownQuote(_ sender: Any?) { toggleBlock(.quote) }
    @objc func markdownCodeBlock(_ sender: Any?) {
        apply(MarkdownFormatting.toggleCodeBlock(in: string as NSString, selection: selectedRange()))
    }
    @objc func markdownDivider(_ sender: Any?) {
        apply(MarkdownFormatting.insertDivider(in: string as NSString, selection: selectedRange()))
    }

    /// Ссылка: адрес и текст спрашиваем в окне — в тексте `](адрес)` скрыт, вписать
    /// его там было бы негде. Выделение попадает в поле текста; пустой текст —
    /// вставится просто адрес.
    @objc func markdownLink(_ sender: Any?) {
        let selection = selectedRange()
        let ns = string as NSString
        let alert = NSAlert()
        alert.messageText = "Link"
        alert.informativeText = "Text is optional \u{2014} without it the address itself is shown."
        let textField = NSTextField(frame: NSRect(x: 0, y: 32, width: 280, height: 24))
        textField.placeholderString = "Text"
        if selection.length > 0, NSMaxRange(selection) <= ns.length {
            textField.stringValue = ns.substring(with: selection)
        }
        let addressField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        addressField.placeholderString = "https://"
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 56))
        fields.addSubview(textField)
        fields.addSubview(addressField)
        alert.accessoryView = fields
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = addressField
        guard alert.runModal() == .alertFirstButtonReturn,
              let url = MarkdownRenderer.linkTarget(addressField.stringValue),
              selection.location <= (string as NSString).length else { return }
        let title = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let markdown = title.isEmpty ? url.absoluteString : "[\(title)](\(url.absoluteString))"
        apply(.init(range: selection, replacement: markdown,
                    selection: NSRange(location: selection.location + (markdown as NSString).length, length: 0)))
    }

    private func toggleMarkdown(_ marker: String) {
        apply(MarkdownFormatting.toggle(marker, in: string as NSString, selection: selectedRange()))
    }

    private func toggleBlock(_ kind: MarkdownFormatting.BlockKind) {
        apply(MarkdownFormatting.toggleBlock(kind, in: string as NSString, selection: selectedRange()))
    }

    /// Через shouldChangeText/didChangeText — правка попадает в ⌘Z и в card.text.
    private func apply(_ edit: MarkdownFormatting.Edit) {
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
    }

    /// Escape в NSTextView штатно уходит в `complete:` и дальше по цепочке
    /// не идёт — поэтому SwiftUI-модификатор .onExitCommand на карточке
    /// его не увидел бы, пока текст в фокусе. Перехватываем здесь и только
    /// когда снаружи реально есть, кому его отдать (Focus Mode).
    override func cancelOperation(_ sender: Any?) {
        guard let onEscape else {
            super.cancelOperation(sender)
            return
        }
        onEscape()
    }

    /// Блок кода, только что скопированный кнопкой, — на секунду галочка.
    private var copiedBlockLocation: Int?

    /// Рисование вокруг Markdown и клики по нему — см. MarkdownBlockDecorator.
    /// Цвет — каретки, а не textColor: тот — цвет первого символа, а он бывает
    /// скрытым (прозрачным), и иконки становились чёрными.
    private var decorator: MarkdownBlockDecorator? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }
        return MarkdownBlockDecorator(
            layoutManager: layoutManager,
            textContainer: textContainer,
            textStorage: textStorage,
            origin: textContainerOrigin,
            textColor: insertionPointColor ?? .white,
            lineColor: dividerLineColor,
            copiedBlockLocation: copiedBlockLocation
        )
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        decorator?.drawBackground()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        decorator?.drawOverlays()
    }

    /// Клик по квадратику отмечает пункт (с ⌘Z); клик по значку в углу блока
    /// кода копирует его текст.
    override func mouseDown(with event: NSEvent) {
        switch decorator?.hit(at: convert(event.locationInWindow, from: nil)) {
        case .copyCode(let block, let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedBlockLocation = block.location
            needsDisplay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard self?.copiedBlockLocation == block.location else { return }
                self?.copiedBlockLocation = nil
                self?.needsDisplay = true
            }
        case .toggleTask(let range, let replacement):
            if shouldChangeText(in: range, replacementString: replacement) {
                textStorage?.replaceCharacters(in: range, with: replacement)
                didChangeText()
            }
        case nil:
            super.mouseDown(with: event)
        }
    }

    /// Единая точка, через которую AppKit проводит ЛЮБОЕ изменение
    /// выделения — мышью (клик, drag), клавиатурой (стрелки, Shift+стрелки,
    /// Cmd+←), программно. В отличие от doCommandBy (который ловит только
    /// именованные клавиатурные команды и не видит мышь вообще), это
    /// гарантированно перехватывает абсолютно все пути — поэтому именно здесь
    /// не даём выделению/курсору заходить ДО конца маркера списка.
    /// После правки `atoms` описывают старый текст: AppKit ставит курсор уже в новом, и
    /// сдвинутый атом маркера следующей строки уносил бы курсор туда. Пока перекраска
    /// (textDidChange) не пересчитала их — пусто.
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        atoms = []
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRange(Self.clampSelectionRange(charRange, in: self, from: selectedRange().location), affinity: affinity, stillSelecting: stillSelectingFlag)
        // super сам инвалидирует только разницу между старым и новым
        // диапазоном выделения — но раз мы подменяем диапазон клэмпом,
        // реально нарисованная на экране область не всегда совпадает с тем,
        // что AppKit считает "предыдущим" для этого расчёта. Из-за этого при
        // живом drag-выделении на экране мог оставаться неочищенный кусок
        // старой подсветки (серая полоса). Полный redraw избавляет от
        // рассинхрона независимо от того, как AppKit посчитал дельту.
        needsDisplay = true
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
        if result {
            onFirstResponderChange?(true)
        }
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
        if result {
            onFirstResponderChange?(false)
            // Синхронный setSelectedRange здесь раньше приводил к
            // залипающему I-beam на других карточках (см. коммит, где это
            // убирали) — похоже, вмешивался в ещё не устаканившийся
            // responder chain. async откладывает его на следующий цикл
            // run loop, когда window.firstResponder уже точно обновлён, но
            // при этом сохраняет исходную цель вызова: без него выделение
            // остаётся видимым на расфокусированной карточке (можно
            // выделить текст сразу в нескольких карточках одновременно), а
            // override setSelectedRange больше не форсирует needsDisplay —
            // отсюда и оставшиеся "фантомные" полосы старой подсветки.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.setSelectedRange(NSRange(location: 0, length: 0))
                // needsDisplay внутри override'а иногда недостаточно —
                // NSTextView сидит как documentView в NSScrollView, и её
                // собственный (возможно, тоже layer-backed) contentView не
                // всегда сам решает перерисоваться вслед за documentView.
                // displayIfNeeded форсирует реальный синхронный flush, а не
                // просто пометку "грязным" до следующего цикла.
                self.enclosingScrollView?.contentView.needsDisplay = true
                self.enclosingScrollView?.needsDisplay = true
                self.displayIfNeeded()
                self.enclosingScrollView?.displayIfNeeded()
            }
        }
        return result
    }

    /// Выделение до правого клика: сам правый клик по тексту выделяет слово
    /// под курсором, и без этого "Ask AI" почти всегда спрашивал бы про одно
    /// слово. Не было своего выделения — вопрос про всю карточку.
    private var selectionBeforeContextMenu: NSRange?
    private var contextMenuPoint: NSPoint = .zero

    override func rightMouseDown(with event: NSEvent) {
        selectionBeforeContextMenu = selectedRange()
        super.rightMouseDown(with: event)
    }

    /// Пункт "Ask AI" — сразу под системным "Ask Siri" (macOS 27+), а где
    /// его нет — первым пунктом с разделителем. Стандартное меню
    /// NSTextView (Cut/Copy/Paste/Spelling…) при этом не трогается.
    override func menu(for event: NSEvent) -> NSMenu? {
        if selectionBeforeContextMenu == nil {
            selectionBeforeContextMenu = selectedRange()
        }
        contextMenuPoint = convert(event.locationInWindow, from: nil)
        guard let menu = super.menu(for: event) else { return nil }

        let item = NSMenuItem(title: "Ask AI", action: #selector(askAI(_:)), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)

        let format = FormatCommand.contextMenuItem(target: self)

        // "Siri" — имя бренда, в локализациях не переводится. Сразу под Ask
        // Siri macOS 27 не рисует иконку пункта — так и задумано, не
        // переставляем.
        if let siriIndex = menu.items.firstIndex(where: { $0.title.contains("Siri") }) {
            menu.insertItem(item, at: siriIndex + 1)
            menu.insertItem(format, at: siriIndex + 2)
        } else {
            menu.insertItem(item, at: 0)
            menu.insertItem(format, at: 1)
            menu.insertItem(.separator(), at: 2)
        }
        return menu
    }

    @objc private func askAI(_ sender: NSMenuItem) {
        let before = selectionBeforeContextMenu ?? NSRange(location: 0, length: 0)
        selectionBeforeContextMenu = nil
        let range = before.length > 0 ? before : NSRange(location: 0, length: 0)
        AskAIPopoverController.show(for: self, range: range, anchor: anchorRect(for: range))
    }

    /// Куда привязать popover: к видимой части выделения, иначе — к месту
    /// правого клика.
    private func anchorRect(for range: NSRange) -> NSRect {
        let clickRect = NSRect(x: contextMenuPoint.x, y: contextMenuPoint.y, width: 1, height: 1)
        guard range.length > 0, let layoutManager, let textContainer else { return clickRect }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        let visible = rect.intersection(visibleRect)
        return visible.isEmpty ? clickRect : visible
    }

    private static func clampSelectionRange(_ range: NSRange, in textView: NSTextView, from old: Int) -> NSRange {
        guard let textStorage = textView.textStorage, textStorage.length > 0 else { return range }
        let ns = textStorage.string as NSString
        let atoms = (textView as? CardNSTextView)?.atoms ?? []
        // Сдвиг курсора на один символ (стрелка) идёт сквозь скрытые символы в
        // сторону движения, иначе ←/→ застревали бы у `**`; остальное
        // (клик, ⌘←, выделение) — к ближайшему допустимому месту.
        let isStep = range.length == 0 && abs(range.location - old) == 1

        func snapped(_ location: Int) -> Int {
            guard let atom = atoms.first(where: { $0.lower <= location && location <= $0.upper }) else { return location }
            guard isStep else { return LiveMarkdown.snap(location, atoms: atoms) }
            let through = old < atom.lower ? atom.upper + 1 : old > atom.upper ? atom.lower - 1 : atom.target
            return (0...ns.length).contains(through) ? LiveMarkdown.snap(through, atoms: atoms) : old
        }

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

        let start = snapped(clamp(range.location))
        let end = snapped(clamp(range.location + range.length))
        let newStart = min(start, end)
        let newEnd = max(start, end)
        return NSRange(location: newStart, length: newEnd - newStart)
    }

    /// Маркер списка, обнаруженный в начале строки.
    enum ListPrefix {
        case bullet
        case numbered(Int)
        case task(length: Int)
        case quote

        var length: Int {
            switch self {
            case .task(let length): return length // "[] ", "[x] ", "- [ ] "
            case .quote: return 2 // "> "
            case .bullet: return 2 // "- "
            case .numbered(let n): return "\(n). ".count
            }
        }

        /// Маркер следующего пункта (без ведущего "\n").
        var nextMarker: String {
            switch self {
            case .bullet: return "- "
            case .task: return "- [ ] "
            case .quote: return "> "
            case .numbered(let n): return "\(n + 1). "
            }
        }
    }

    /// "- " -> маркированный список, "1. "/"12. " и т.п. -> нумерованный,
    /// "[] "/"[x] "/"- [ ] " -> чек-лист, "> " -> цитата.
    /// Отдельной "активации" для чисел не нужно — "1. " уже выглядит как
    /// корректный маркер, распознаётся здесь же в момент нажатия Enter.
    static func detectListPrefix(in ns: NSString, lineRange: NSRange) -> ListPrefix? {
        guard lineRange.length >= 2 else { return nil }
        let line = ns.substring(with: lineRange)

        // Новый пункт чек-листа — всегда пустой `- [ ] `, даже после отмеченного.
        if let match = line.range(of: MarkdownStyler.taskPattern, options: .regularExpression) {
            return .task(length: (String(line[match]) as NSString).length)
        }
        if line.hasPrefix("> ") {
            return .quote
        }
        if line.hasPrefix("- ") {
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
    /// Markdown карточки — хранится и редактируется как есть, раскраска —
    /// MarkdownRenderer.
    @Binding var text: String
    @Binding var isFocused: Bool
    var cardSize: CGSize
    var onTextChange: () -> Void
    var onFocusChange: (Bool) -> Void
    /// Escape внутри текста. nil — обычное поведение NSTextView.
    var onEscape: (() -> Void)?
    /// Шрифт/цвет из Settings → Appearance. Параметр, а не чтение
    /// AppearanceSettings внутри: смена стиля должна приводить к
    /// updateNSView, а это происходит только при изменении входных данных.
    var typography: CardTypography

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
        // Карточка прокручивается только вертикально — и без горизонтальной
        // «пружины» трекпада.
        scrollView.horizontalScrollElasticity = .none
        scrollView.borderType = .noBorder

        let textView = CardNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.onFirstResponderChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.handleFirstResponderChange(focused)
        }
        textView.onEscape = onEscape
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = true
        // Изображения не поддерживаются: выключенный импорт графики не даёт
        // картинке попасть в текст через paste или drag-and-drop.
        textView.importsGraphics = false
        // Шрифт и цвет фрагмента в Markdown не сохранить — панели не нужны.
        textView.usesFontPanel = false
        textView.allowsUndo = true
        // Ссылки, в том числе голые адреса, расставляет MarkdownRenderer.
        textView.isAutomaticLinkDetectionEnabled = false
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
        Self.applyChrome(typography, to: textView)

        textView.layoutManager?.delegate = textView.bulletGlyphs
        textView.string = text
        context.coordinator.lastTypography = typography
        Self.restyle(textView, typography: typography)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CardNSTextView else { return }

        // Переприсваивается на каждое обновление, а не берётся из
        // coordinator.parent (SwiftUI его не освежает) — иначе при входе в
        // Focus Mode текст остался бы со старым, пустым обработчиком.
        textView.onEscape = onEscape

        // Стиль поменяли в Settings, пока карточка открыта — перекрашиваем
        // уже набранный текст на месте (сам текст не меняется).
        if context.coordinator.lastTypography != typography {
            let selectedRanges = textView.selectedRanges
            context.coordinator.lastTypography = typography
            Self.restyle(textView, typography: typography)
            textView.selectedRanges = selectedRanges
            Self.applyChrome(typography, to: textView)
            textView.needsDisplay = true
        }

        let innerWidth = max(cardSize.width - Self.horizontalTextInset * 2, 10)
        if let container = textView.textContainer,
           abs(container.size.width - innerWidth) > 0.5 {
            container.size = NSSize(width: innerWidth, height: .greatestFiniteMagnitude)
            textView.layoutManager?.invalidateLayout(
                forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length),
                actualCharacterRange: nil
            )
        }

        // Обновляем содержимое NSTextView, только если оно реально
        // разошлось с привязкой — иначе бесконечный цикл
        // (textDidChange -> $text = ... -> updateNSView -> string = ... -> ...).
        //
        // Текст поменялся снаружи (AI-действие, импорт бэкапа, правка с
        // другого Mac через iCloud).
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            // Записи отмен хранят позиции в прежнем тексте — применённые к
            // новому, они ломали бы ⌘Z (и менеджер отмен всего окна).
            context.coordinator.undoManager.removeAllActions()
            textView.string = text
            Self.restyle(textView, typography: typography)
            let length = (textView.string as NSString).length
            textView.selectedRanges = selectedRanges.map { value in
                let range = value.rangeValue
                let location = min(range.location, length)
                return NSValue(range: NSRange(location: location, length: min(range.length, length - location)))
            }
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

    /// Перекраска и пересчёт мест, куда курсору нельзя (скрытые символы).
    /// Во время составного ввода (IME) не трогаем — смена атрибутов
    /// посреди набора его ломает; после подтверждения придёт новый вызов.
    fileprivate static func restyle(_ textView: NSTextView, typography: CardTypography) {
        guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }
        MarkdownRenderer.style(storage, typography: typography)
        (textView as? CardNSTextView)?.atoms = LiveMarkdown.atoms(MarkdownStyler.parse(storage.string), length: storage.length)
        textView.typingAttributes = MarkdownRenderer.baseAttributes(typography)
    }

    /// Всё, что зависит от стиля помимо самого текста: цвет по умолчанию,
    /// каретка, атрибуты набора и линия разделителя.
    private static func applyChrome(_ typography: CardTypography, to textView: CardNSTextView) {
        textView.textColor = typography.color
        textView.insertionPointColor = typography.color
        textView.typingAttributes = MarkdownRenderer.baseAttributes(typography)
        textView.dividerLineColor = typography.color.withAlphaComponent(0.22)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CardTextView
        var didRequestFocus = false
        /// Стиль, которым сейчас нарисован текст — см. updateNSView.
        var lastTypography: CardTypography?
        weak var textView: NSTextView?
        /// Своя история отмен у каждой карточки: общий менеджер окна делили
        /// все карточки и поля Ask AI — ⌘Z «проваливался» в чужую историю,
        /// применял её к чужому тексту и ломался во всём окне.
        let undoManager = UndoManager()

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }
        private var typography: CardTypography { lastTypography ?? AppearanceSettings.shared.cardTypography }

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

            // Заголовки, цитаты, пункты, `**`, ссылки, ```: что стереть, решает LiveMarkdown.
            if let range = LiveMarkdown.backspaceRange(at: cursor.location, text: textView.string) {
                guard replaceUndoably(range, with: "", in: textView) else { return true }
                refreshLayout(of: textView, from: range.location)
                textView.setSelectedRange(NSRange(location: range.location, length: 0))
                return true
            }

            let ns = textView.string as NSString
            var lineRange = ns.paragraphRange(for: NSRange(location: cursor.location, length: 0))
            if lineRange.length > 0,
               ns.substring(with: NSRange(location: lineRange.location + lineRange.length - 1, length: 1)) == "\n" {
                lineRange.length -= 1
            }

            // Остался нумерованный список: `1. ` скрыт не бывает.
            guard let prefix = CardNSTextView.detectListPrefix(in: ns, lineRange: lineRange) else { return false }
            // Курсор должен стоять ровно сразу после маркера — иначе это
            // обычный backspace где-то в тексте пункта, не наша забота.
            guard cursor.location == lineRange.location + prefix.length else { return false }

            guard replaceUndoably(NSRange(location: lineRange.location, length: prefix.length), with: "", in: textView) else { return true }
            refreshLayout(of: textView, from: lineRange.location)
            textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
            return true
        }

        /// Правка текста самим редактором — как ввод с клавиатуры, через
        /// shouldChangeText/didChangeText: попадает в историю отмен. Прямая
        /// правка textStorage в обход неё расходилась с историей: ⌘Z откатывал
        /// только набранное (маркеры списка оставались), а затем ломался
        /// менеджер отмен — общий на всё окно, ⌘Z переставал работать везде.
        private func replaceUndoably(_ range: NSRange, with string: String, in textView: NSTextView) -> Bool {
            guard textView.shouldChangeText(in: range, replacementString: string) else { return false }
            textView.textStorage?.replaceCharacters(in: range, with: string)
            textView.didChangeText()
            return true
        }

        /// Без явной инвалидации TextKit мог рисовать по ещё не пересчитанному
        /// layout сразу после правки — маркер либо «приклеивался» к предыдущей
        /// строке, либо для удаления пустого пункта требовалось нажать Enter дважды.
        private func refreshLayout(of textView: NSTextView, from location: Int) {
            let affected = NSRange(location: location, length: max(0, (textView.string as NSString).length - location))
            textView.layoutManager?.invalidateLayout(forCharacterRange: affected, actualCharacterRange: nil)
            textView.layoutManager?.ensureLayout(forCharacterRange: affected)
            textView.needsDisplay = true
        }

        /// Enter на непустом пункте списка (`- текст`, `N. текст`, `- [ ] текст`,
        /// `> текст`) продолжает список новым маркером на следующей строке;
        /// Enter на пустом пункте убирает маркер вместо
        /// переноса строки — как в стандартных списках Notes/TextEdit.
        private func continueListIfNeeded(in textView: NSTextView) -> Bool {
            let cursor = textView.selectedRange()
            guard cursor.length == 0 else { return false }

            // Конец строки списка/цитаты, второй Return в блоке кода: правило — LiveMarkdown.
            if let edit = LiveMarkdown.newline(at: cursor.location, text: textView.string) {
                guard replaceUndoably(edit.range, with: edit.replacement, in: textView) else { return true }
                refreshLayout(of: textView, from: edit.range.location)
                textView.setSelectedRange(edit.selection)
                return true
            }

            let ns = textView.string as NSString
            var lineRange = ns.paragraphRange(for: NSRange(location: cursor.location, length: 0))
            if lineRange.length > 0,
               ns.substring(with: NSRange(location: lineRange.location + lineRange.length - 1, length: 1)) == "\n" {
                lineRange.length -= 1
            }

            // Остаток: Return в середине пункта (текст после курсора уходит в новый пункт).
            guard let prefix = CardNSTextView.detectListPrefix(in: ns, lineRange: lineRange) else { return false }

            let contentRange = NSRange(location: lineRange.location + prefix.length, length: lineRange.length - prefix.length)
            let hasContent = contentRange.length > 0
                && !ns.substring(with: contentRange).trimmingCharacters(in: .whitespaces).isEmpty

            let newCursorLocation: Int
            if hasContent {
                let insertion = "\n" + prefix.nextMarker
                guard replaceUndoably(cursor, with: insertion, in: textView) else { return true }
                newCursorLocation = cursor.location + (insertion as NSString).length
            } else {
                guard replaceUndoably(lineRange, with: "", in: textView) else { return true }
                newCursorLocation = lineRange.location
            }
            refreshLayout(of: textView, from: lineRange.location)
            // Курсор — после правки: пока она не применена, выставление
            // выделения уводило NSTextView в зависшее состояние.
            textView.setSelectedRange(NSRange(location: newCursorLocation, length: 0))
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            CardTextView.restyle(textView, typography: typography)
            // Новая разметка — курсор мог оказаться внутри скрытых символов.
            textView.setSelectedRange(textView.selectedRange())
            parent.text = textView.string
            parent.onTextChange()
        }

        /// Пробел после `[]`, `[ ]`, `[x]`, `- []` в начале строки — вместо
        /// него стандартный `- [ ] ` (см. MarkdownFormatting.standardTaskMarker).
        /// Именно здесь, обычным вводом (insertText), а не правкой текста после
        /// textDidChange: та ломала запись набора в истории отмен — ⌘Z то не
        /// срабатывал, то оставлял обрывки вроде `- `.
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard replacementString == " ", range.length == 0, !textView.hasMarkedText(),
                  textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true else { return true }
            let ns = textView.string as NSString
            let lineStart = ns.lineRange(for: NSRange(location: range.location, length: 0)).location
            let prefix = NSRange(location: lineStart, length: range.location - lineStart)
            guard let standard = MarkdownFormatting.standardTaskMarker(typingSpaceAfter: ns.substring(with: prefix)) else { return true }
            textView.insertText(standard, replacementRange: prefix)
            return false
        }

        /// Единственный реальный источник смены фокуса — см. комментарий у
        /// CardNSTextView.onFirstResponderChange. textDidBeginEditing/
        /// textDidEndEditing из NSTextViewDelegate на практике не
        /// срабатывают на обычный клик в этом кастомном NSTextView.
        func handleFirstResponderChange(_ focused: Bool) {
            DispatchQueue.main.async {
                self.parent.isFocused = focused
                self.parent.onFocusChange(focused)
            }
        }
    }
}
