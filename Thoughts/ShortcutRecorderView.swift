import SwiftUI
import AppKit

/// Кнопка-рекордер глобального сочетания: клик → "Type Shortcut…" → первое
/// нажатие с ⌘/⌃/⌥ становится новым сочетанием. Esc отменяет запись,
/// Delete возвращает сочетание по умолчанию. Клавиши ловятся по физическому
/// keyCode, как в KeyCodeCaptureView.
struct ShortcutRecorderView: View {
    var shortcut: HotKeyShortcut
    var onRecord: (HotKeyShortcut) -> Void
    var onReset: () -> Void
    /// Начало/конец записи — владелец хоткея снимает его на это время,
    /// иначе нажатие текущего сочетания перехватил бы Carbon.
    var onRecordingChange: (Bool) -> Void = { _ in }

    @State private var isRecording = false

    var body: some View {
        Button {
            setRecording(!isRecording)
        } label: {
            Text(isRecording ? "Type Shortcut\u{2026}" : shortcut.displayString)
                .font(.system(size: 12, weight: .medium))
                .frame(minWidth: 100)
        }
        .background {
            if isRecording {
                RecorderCaptureView(
                    onCapture: { captured in
                        setRecording(false)
                        onRecord(captured)
                    },
                    onReset: {
                        setRecording(false)
                        onReset()
                    },
                    onCancel: { setRecording(false) }
                )
                .frame(width: 1, height: 1)
            }
        }
    }

    private func setRecording(_ recording: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        onRecordingChange(recording)
    }
}

private struct RecorderCaptureView: NSViewRepresentable {
    var onCapture: (HotKeyShortcut) -> Void
    var onReset: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        update(view)
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        update(nsView)
    }

    private func update(_ view: CaptureView) {
        view.onCapture = onCapture
        view.onReset = onReset
        view.onCancel = onCancel
    }

    final class CaptureView: NSView {
        var onCapture: ((HotKeyShortcut) -> Void)?
        var onReset: (() -> Void)?
        var onCancel: (() -> Void)?
        private var isFinished = false

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            handle(event)
        }

        /// Сочетания с ⌘ приходят сюда раньше keyDown — без перехвата их
        /// забрало бы меню приложения (⌘L, ⌘F и т.п.).
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self, event.type == .keyDown else { return false }
            handle(event)
            return true
        }

        /// Клик мимо (фокус ушёл) — запись отменяется.
        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()
            if result { finish { onCancel?() } }
            return result
        }

        private func handle(_ event: NSEvent) {
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            switch Int(event.keyCode) {
            case 53 where flags.isEmpty: // Escape
                finish { onCancel?() }
            case 51 where flags.isEmpty, 117 where flags.isEmpty: // Delete, Forward Delete
                finish { onReset?() }
            default:
                if let shortcut = HotKeyShortcut.from(event: event) {
                    finish { onCapture?(shortcut) }
                } else {
                    NSSound.beep()
                }
            }
        }

        private func finish(_ action: () -> Void) {
            guard !isFinished else { return }
            isFinished = true
            action()
        }
    }
}
