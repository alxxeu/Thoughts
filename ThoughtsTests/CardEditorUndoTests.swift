import AppKit
import SwiftUI
import Testing
@testable import Thoughts

/// ⌘Z после правок, которые делает сам редактор (продолжение списка, снятие
/// пустого пункта), — на настоящем NSTextView с менеджером отмен окна.
@MainActor
struct CardEditorUndoTests {
    @MainActor private final class Harness {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let coordinator: CardTextView.Coordinator
        var undo: UndoManager { textView.undoManager! }

        init() {
            let editor = CardTextView(
                text: .constant(""), isFocused: .constant(true), cardSize: CGSize(width: 300, height: 300),
                onTextChange: {}, onFocusChange: { _ in }, onEscape: nil,
                typography: CardTypography(font: .systemFont(ofSize: 15), color: .white)
            )
            coordinator = editor.makeCoordinator()
            textView.allowsUndo = true
            textView.delegate = coordinator
            coordinator.textView = textView
            window.contentView = textView
            window.makeFirstResponder(textView)
            undo.groupsByEvent = false
        }

        /// Один шаг пользователя — одна группа отмены, как отдельное событие.
        func step(_ action: () -> Void) {
            undo.beginUndoGrouping()
            action()
            textView.breakUndoCoalescing()
            undo.endUndoGrouping()
        }

        func type(_ s: String) { step { textView.insertText(s, replacementRange: textView.selectedRange()) } }

        func enter() {
            step {
                if !coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:))) {
                    textView.insertNewline(nil)
                }
            }
        }
    }

    @Test func undoRemovesAutoContinuedListMarkers() {
        let h = Harness()
        h.type("- [ ] one")
        h.enter()          // продолжает список: "\n- [ ] "
        h.type("two")
        h.enter()          // ещё пункт
        h.enter()          // пустой пункт — снимается
        #expect(h.textView.string == "- [ ] one\n- [ ] two\n")

        while h.undo.canUndo { h.undo.undo() }
        // Раньше маркеры, вставленные редактором, оставались висеть.
        #expect(h.textView.string == "")

        while h.undo.canRedo { h.undo.redo() }
        #expect(h.textView.string == "- [ ] one\n- [ ] two\n")
    }

    @Test func undoRestoresMarkerRemovedByBackspace() {
        let h = Harness()
        h.type("- item")
        h.step { h.textView.setSelectedRange(NSRange(location: 2, length: 0)) }
        h.step {
            _ = h.coordinator.textView(h.textView, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
        }
        #expect(h.textView.string == "item")
        h.undo.undo()
        #expect(h.textView.string == "- item")
    }
}
