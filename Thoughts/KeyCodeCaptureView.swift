import SwiftUI
import AppKit

/// Ловит нажатия клавиш по их физическому коду (NSEvent.keyCode), а не по
/// итоговому символу — поэтому passcode не зависит от активной раскладки
/// клавиатуры: одна и та же физическая клавиша даёт один и тот же код
/// что в английской, что в русской раскладке (и с буквами, и с цифрами).
/// Ничего не рисует — обычный NSView без текстовой системы, поэтому в
/// отличие от скрытого TextField у него в принципе нет курсора/каретки,
/// которые могли бы "протечь" наружу.
struct KeyCodeCaptureView: NSViewRepresentable {
    var onKeyCode: (UInt16) -> Void
    var onDelete: () -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onKeyCode = onKeyCode
        view.onDelete = onDelete
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onKeyCode = onKeyCode
        nsView.onDelete = onDelete
        // Переустанавливаем first responder на каждое обновление — дёшево,
        // если уже так, зато гарантирует, что фокус не потеряется при
        // смене экрана/Space под тем же экземпляром view.
        DispatchQueue.main.async {
            if nsView.window?.firstResponder !== nsView {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class CaptureView: NSView {
        var onKeyCode: ((UInt16) -> Void)?
        var onDelete: (() -> Void)?

        private static let deleteKeyCode: UInt16 = 51
        private static let forwardDeleteKeyCode: UInt16 = 117

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == Self.deleteKeyCode || event.keyCode == Self.forwardDeleteKeyCode {
                onDelete?()
            } else {
                onKeyCode?(event.keyCode)
            }
        }
    }
}

/// Канонический вид "passcode" для хранения/сверки в PasscodeStore —
/// последовательность физических кодов клавиш, а не символов.
enum PasscodeEncoding {
    static func string(from codes: [UInt16]) -> String {
        codes.map(String.init).joined(separator: ",")
    }
}
