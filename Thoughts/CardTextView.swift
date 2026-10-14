import SwiftUI
import AppKit

// MARK: - Custom NSTextView (plain-text paste + divider drawing)

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

    // Производный от цвета текста (Settings → Appearance), а не
    // адаптивный labelColor — фон карточки (CardSurfaceStyle) не
    // переключается в светлый в Light Mode, так что линии поверх него
    // должны следовать за текстом, а не за темой.
    var dividerLineColor = CardTypography.defaultTextColor.withAlphaComponent(0.22)
    /// Делегат вёрстки, прячущий служебные символы Markdown. layoutManager
    /// держит делегата слабо — храним здесь.
    let glyphHider = MarkdownGlyphHider()

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
        insertText(plain, replacementRange: selectedRange())
    }

    // MARK: Format (⌘B, ⌘I, …) — меню шлёт эти действия по responder chain

    @objc func markdownBold(_ sender: Any?) { toggleMarkdown("**") }
    @objc func markdownItalic(_ sender: Any?) { toggleMarkdown("*") }
    @objc func markdownUnderline(_ sender: Any?) { toggleMarkdown("~") }
    @objc func markdownStrikethrough(_ sender: Any?) { toggleMarkdown("~~") }
    @objc func markdownHighlight(_ sender: Any?) { toggleMarkdown("==") }

    /// Через shouldChangeText/didChangeText — правка попадает в ⌘Z и в card.text.
    private func toggleMarkdown(_ marker: String) {
        let edit = MarkdownFormatting.toggle(marker, in: string as NSString, selection: selectedRange())
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

    /// Поля блоков на всю ширину. Код — по строкам целиком (узкие строки ```
    /// и есть его поля); цитата — по самому тексту плюс `textPadding` сверху
    /// и снизу: отступ перед первым абзацем TextKit не учитывает, и без
    /// этого поле цитаты в начале карточки упиралось в текст.
    private func blockBoxes(_ key: NSAttributedString.Key, textPadding: CGFloat? = nil) -> [(range: NSRange, rect: NSRect)] {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return [] }
        var boxes: [(NSRange, NSRect)] = []
        var seen = Set<Int>()
        textStorage.enumerateAttribute(key, in: NSRange(location: 0, length: textStorage.length)) { value, _, _ in
            guard let block = (value as? NSValue)?.rangeValue, seen.insert(block.location).inserted else { return }
            var rect = NSRect.null
            let glyphs = layoutManager.glyphRange(forCharacterRange: block, actualCharacterRange: nil)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, usedRect, _, _, _ in
                rect = rect.union(textPadding == nil ? lineRect : usedRect)
            }
            guard !rect.isNull else { return }
            if let textPadding { rect = rect.insetBy(dx: 0, dy: -textPadding) }
            rect.origin.x = textContainerOrigin.x - 6
            rect.size.width = textContainer.size.width + 12
            rect.origin.y += textContainerOrigin.y
            boxes.append((block, rect))
        }
        return boxes
    }

    /// Под текстом: подложка блоков кода, поле цитаты с полосой слева.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        for (_, box) in blockBoxes(MarkdownRenderer.codeBlockKey) {
            dividerLineColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        }

        let accent = NSColor.controlAccentColor
        for (_, box) in blockBoxes(MarkdownRenderer.quoteKey, textPadding: 6) {
            let shape = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
            accent.withAlphaComponent(0.14).setFill()
            shape.fill()
            // Сплошная полоса по левому краю — внутри скругления поля.
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            accent.setFill()
            NSRect(x: box.minX, y: box.minY, width: 3, height: box.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Иконка SF Symbols одного цвета.
    private func drawSymbol(_ name: String, color: NSColor, in rect: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)?
            .draw(in: rect)
    }

    /// Кнопка/значок в правом верхнем углу поля блока.
    private func cornerIconRect(in box: NSRect) -> NSRect {
        NSRect(x: box.maxX - 20, y: box.minY + 6, width: 12, height: 12)
    }

    /// Блок кода, только что скопированный кнопкой, — на секунду галочка.
    private var copiedBlockLocation: Int?

    /// Рисует линии разделителей `---` поверх текста (строки отмечены
    /// MarkdownRenderer.dividerKey) и для каждой берёт СВЕЖИЙ line fragment
    /// rect у layoutManager — без риска нарисовать по устаревшему layout.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let layoutManager, let textContainer, let textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let origin = textContainerOrigin

        textStorage.enumerateAttribute(MarkdownRenderer.dividerKey, in: fullRange) { value, range, _ in
            guard value != nil else { return }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let y = (origin.y + lineRect.midY).rounded()

            let path = NSBezierPath()
            path.move(to: NSPoint(x: origin.x, y: y))
            path.line(to: NSPoint(x: origin.x + textContainer.size.width, y: y))
            path.lineWidth = 1
            dividerLineColor.setStroke()
            path.stroke()
        }

        // Квадратики чек-листов — слева, на отступе строки.
        textStorage.enumerateAttribute(MarkdownRenderer.taskBoxKey, in: fullRange) { value, range, _ in
            guard let done = value as? Bool, let box = taskBoxRect(for: range) else { return }
            let color = textColor ?? .white
            let path = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
            if done {
                color.withAlphaComponent(0.55).setFill()
                path.fill()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: box.minX + box.width * 0.25, y: box.midY))
                check.line(to: NSPoint(x: box.minX + box.width * 0.43, y: box.maxY - box.height * 0.27))
                check.line(to: NSPoint(x: box.maxX - box.width * 0.22, y: box.minY + box.height * 0.28))
                check.lineWidth = 1.6
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                // Галочка контрастна заливке: на светлом тексте — тёмная, на тёмном — светлая.
                let isLight = (color.usingColorSpace(.sRGB)?.brightnessComponent ?? 1) > 0.5
                (isLight ? NSColor.black : NSColor.white).withAlphaComponent(0.8).setStroke()
                check.stroke()
            } else {
                path.lineWidth = 1.2
                color.withAlphaComponent(0.6).setStroke()
                path.stroke()
            }
        }

        // Значки в углу полей, оба серые: « у цитаты, копирование у кода.
        let iconColor = (textColor ?? .white).withAlphaComponent(0.45)
        for (_, box) in blockBoxes(MarkdownRenderer.quoteKey, textPadding: 6) {
            drawSymbol("quote.closing", color: iconColor, in: cornerIconRect(in: box))
        }
        for (block, box) in blockBoxes(MarkdownRenderer.codeBlockKey) {
            let copied = copiedBlockLocation == block.location
            drawSymbol(copied ? "checkmark" : "doc.on.doc", color: iconColor, in: cornerIconRect(in: box))
        }
    }

    /// Квадрат чек-листа на отступе строки, по центру строчных букв.
    private func taskBoxRect(for range: NSRange) -> NSRect? {
        guard let layoutManager, let textStorage, range.location < textStorage.length else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = layoutManager.location(forGlyphAt: glyph).y
        let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 15)
        let side = (font.capHeight * 1.35).rounded()
        let centerY = textContainerOrigin.y + line.minY + baseline - font.xHeight / 2
        return NSRect(x: textContainerOrigin.x + 1, y: centerY - side / 2, width: side, height: side)
    }

    /// Текст блока кода без строк ```.
    private func codeContent(of block: NSRange) -> String {
        var lines = (string as NSString).substring(with: block).components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true { lines.removeFirst() }
        if lines.count > 0, lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// Клик по квадратику отмечает пункт (`[]` ↔ `[x]`, с ⌘Z); клик по
    /// значку в углу блока кода копирует его текст.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let (block, _) = blockBoxes(MarkdownRenderer.codeBlockKey).first(where: { cornerIconRect(in: $0.rect).insetBy(dx: -4, dy: -4).contains(point) }) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(codeContent(of: block), forType: .string)
            copiedBlockLocation = block.location
            needsDisplay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard self?.copiedBlockLocation == block.location else { return }
                self?.copiedBlockLocation = nil
                self?.needsDisplay = true
            }
            return
        }
        if let textStorage, textStorage.length > 0 {
            var hit: NSRange?
            textStorage.enumerateAttribute(MarkdownRenderer.taskBoxKey, in: NSRange(location: 0, length: textStorage.length)) { value, range, stop in
                guard value != nil, let box = taskBoxRect(for: range), box.insetBy(dx: -3, dy: -3).contains(point) else { return }
                hit = range
                stop.pointee = true
            }
            if let space = hit {
                // Содержимое скобок перед пробелом: `[]`/`[ ]` ↔ `[x]`.
                let ns = string as NSString
                let close = space.location - 1
                var open = close - 1
                while open > 0, ns.character(at: open) != 0x5B { open -= 1 } // "["
                let inside = NSRange(location: open + 1, length: close - open - 1)
                let isDone = ns.substring(with: inside).lowercased() == "x"
                let replacement = isDone ? " " : "x"
                if shouldChangeText(in: inside, replacementString: replacement) {
                    textStorage.replaceCharacters(in: inside, with: replacement)
                    didChangeText()
                }
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// Единая точка, через которую AppKit проводит ЛЮБОЕ изменение
    /// выделения — мышью (клик, drag), клавиатурой (стрелки, Shift+стрелки,
    /// Cmd+←), программно. В отличие от doCommandBy (который ловит только
    /// именованные клавиатурные команды и не видит мышь вообще), это
    /// гарантированно перехватывает абсолютно все пути — поэтому именно здесь
    /// не даём выделению/курсору заходить ДО конца маркера списка.
    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRange(Self.clampSelectionRange(charRange, in: self), affinity: affinity, stillSelecting: stillSelectingFlag)
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

        // "Siri" — имя бренда, в локализациях не переводится. Сразу под Ask
        // Siri macOS 27 не рисует иконку пункта — так и задумано, не
        // переставляем.
        if let siriIndex = menu.items.firstIndex(where: { $0.title.contains("Siri") }) {
            menu.insertItem(item, at: siriIndex + 1)
        } else {
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
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

        textView.layoutManager?.delegate = textView.glyphHider
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

        // Требование 6: обновляем содержимое NSTextView только если оно
        // реально разошлось с привязкой — иначе получаем бесконечный цикл
        // (textDidChange -> $text = ... -> updateNSView -> setAttributedString -> ...).
        //
        // Текст поменялся снаружи (AI-действие, импорт бэкапа, правка с
        // другого Mac через iCloud).
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
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

    /// Перекраска с учётом курсора: символы фрагмента рядом с ним видны.
    /// Во время составного ввода (IME) не трогаем — смена атрибутов
    /// посреди набора его ломает; после подтверждения придёт новый вызов.
    fileprivate static func restyle(_ textView: NSTextView, typography: CardTypography) {
        guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }
        let isFocused = textView.window?.firstResponder === textView
        MarkdownRenderer.style(storage, typography: typography, selection: isFocused ? textView.selectedRange() : nil)
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
                let insertion = "\n" + prefix.nextMarker
                textView.textStorage?.replaceCharacters(in: cursor, with: insertion)
                newCursorLocation = cursor.location + (insertion as NSString).length
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
            normalizeTaskMarkers(in: textView)
            CardTextView.restyle(textView, typography: typography)
            parent.text = textView.string
            parent.onTextChange()
        }

        /// `[]`, `[ ]`, `- []`, `[x]` → стандартные `- [ ] ` / `- [x] `: так их
        /// понимают Notion и другие Markdown-приложения. Пока идёт IME-набор —
        /// не трогаем. Повторный textDidChange после правки уже ничего не найдёт.
        private func normalizeTaskMarkers(in textView: NSTextView) {
            guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }
            let ns = textView.string as NSString
            var edits: [(range: NSRange, marker: String)] = []
            for paragraph in MarkdownStyler.parse(textView.string) {
                guard case .task(let done) = paragraph.block, let marker = paragraph.blockMarker else { continue }
                let standard = done ? "- [x] " : "- [ ] "
                if ns.substring(with: marker) != standard { edits.append((marker, standard)) }
            }
            guard !edits.isEmpty else { return }
            // Курсор — туда же относительно текста: после маркера, если был в нём.
            // С конца к началу: более ранние правки сдвигают позицию, более
            // поздние на неё не влияют — диапазоны правок в исходных координатах.
            var cursor = textView.selectedRange().location
            for edit in edits.reversed() {
                let newLength = (edit.marker as NSString).length
                if NSMaxRange(edit.range) <= cursor {
                    cursor += newLength - edit.range.length
                } else if edit.range.location < cursor {
                    cursor = edit.range.location + newLength
                }
            }
            // С конца — чтобы диапазоны раньше по тексту не сдвигались.
            for edit in edits.reversed() where textView.shouldChangeText(in: edit.range, replacementString: edit.marker) {
                storage.replaceCharacters(in: edit.range, with: edit.marker)
            }
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: min(cursor, storage.length), length: 0))
        }

        /// Курсор сдвинулся — показываем символы фрагмента, к которому он
        /// подошёл, и прячем у того, от которого ушёл.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            CardTextView.restyle(textView, typography: typography)
            textView.needsDisplay = true
        }

        /// Единственный реальный источник смены фокуса — см. комментарий у
        /// CardNSTextView.onFirstResponderChange. textDidBeginEditing/
        /// textDidEndEditing из NSTextViewDelegate на практике не
        /// срабатывают на обычный клик в этом кастомном NSTextView.
        func handleFirstResponderChange(_ focused: Bool) {
            DispatchQueue.main.async {
                self.parent.isFocused = focused
                self.parent.onFocusChange(focused)
                // Вне фокуса все служебные символы скрыты.
                if let textView = self.textView {
                    CardTextView.restyle(textView, typography: self.typography)
                }
            }
        }
    }
}
