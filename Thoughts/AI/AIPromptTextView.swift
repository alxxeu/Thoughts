import SwiftUI
import AppKit

/// Простой многострочный ввод для панели Ask AI — не через SwiftUI
/// TextEditor (у него нет способа перехватить именно Return/Shift+Return
/// по отдельности), а через свой NSTextView, как уже сделано для карточек
/// в CardTextView.swift.
private final class AIPromptNSTextView: NSTextView {
    var onSend: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let returnKeyCodes: Set<UInt16> = [36, 76] // Return, numpad Enter
        // hasMarkedText() — не перехватываем Return во время набора через
        // IME (подтверждение варианта в композиции для китайского/японского
        // и т.п.), иначе композиция ломается.
        guard returnKeyCodes.contains(event.keyCode), !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }

        let isShiftHeld = event.modifierFlags.contains(.shift)
        let sendsOnShift = AISettings.shared.sendKeyBinding == .shiftReturnSends
        if isShiftHeld == sendsOnShift {
            onSend?()
        } else {
            super.keyDown(with: event)
        }
    }
}

struct AIPromptTextView: NSViewRepresentable {
    @Binding var text: String
    /// true → просит взять фокус (напр. в момент открытия панели Ask AI).
    /// Не двусторонний — обратной связи "фокус потерян" здесь не нужно,
    /// закрытие панели по клику вовне решается отдельно через .clearTextSelection.
    var shouldFocus: Bool
    var onSend: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = AIPromptNSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = NSColor.white.withAlphaComponent(0.85)
        textView.insertionPointColor = NSColor.white.withAlphaComponent(0.85)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.onSend = onSend

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? AIPromptNSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.onSend = onSend

        if shouldFocus {
            if !context.coordinator.didRequestFocus {
                context.coordinator.didRequestFocus = true
                if nsView.window?.firstResponder !== textView {
                    nsView.window?.makeFirstResponder(textView)
                }
            }
        } else {
            context.coordinator.didRequestFocus = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AIPromptTextView
        var didRequestFocus = false

        init(_ parent: AIPromptTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
