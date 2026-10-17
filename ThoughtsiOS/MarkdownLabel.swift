import SwiftUI
import UIKit

/// Текст карточки в ленте — тем же движком, что редактор (LiveMarkdownStyler +
/// LiveLayoutManager), только мельче и без правки. Касания разбирает SwiftUI:
/// `MarkdownLabelProbe.hit(at:)` отвечает, попал ли палец в квадратик или ссылку.
struct MarkdownLabel: UIViewRepresentable {
    let text: String
    let probe: MarkdownLabelProbe
    var size: CGFloat = 15

    func makeUIView(context: Context) -> UITextView {
        let storage = NSTextStorage()
        let layout = LiveLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let view = UITextView(frame: .zero, textContainer: container)
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.isUserInteractionEnabled = false // касания — в SwiftUI (CardRow)
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        probe.textView = view
        guard view.textStorage.string != text else { return }
        view.text = text
        LiveMarkdownStyler.style(view.textStorage, size: size)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }
}

/// Что под пальцем в MarkdownLabel — в координатах самой метки.
final class MarkdownLabelProbe {
    weak var textView: UITextView?

    enum Hit {
        case task(MarkdownFormatting.Edit)
        case link(URL)
    }

    func hit(at point: CGPoint) -> Hit? {
        guard let layout = textView?.layoutManager as? LiveLayoutManager else { return nil }
        if let edit = layout.taskToggle(at: point, origin: .zero) { return .task(edit) }
        if let url = layout.link(at: point, origin: .zero) { return .link(url) }
        return nil
    }
}
