import SwiftUI

/// Markdown карточки как в ленте: тот же разбор, что на Mac (MarkdownStyler),
/// символы разметки спрятаны. Задачи — кнопки (тап меняет `[ ]` ↔ `[x]`).
struct MarkdownPreview: View {
    let text: String
    var onToggleTask: ((MarkdownStyler.Paragraph) -> Void)? = nil

    var body: some View {
        let paragraphs = MarkdownStyler.parse(text)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                row(p)
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ p: MarkdownStyler.Paragraph) -> some View {
        switch p.block {
        case .heading(let level):
            inline(p).font(.system(size: level == 1 ? 20 : level == 2 ? 17 : 15, weight: .semibold))
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•"); inline(p) }
        case .numbered:
            inline(p, keepMarker: true)
        case .task(let done):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button { onToggleTask?(p) } label: {
                    Image(systemName: done ? "checkmark.square.fill" : "square")
                }
                .buttonStyle(.plain)
                .disabled(onToggleTask == nil)
                inline(p)
                    .strikethrough(done)
                    .foregroundStyle(done ? Theme.secondary : Theme.text)
            }
        case .quote:
            HStack(spacing: 8) {
                Capsule().fill(Theme.secondary).frame(width: 3)
                inline(p).foregroundStyle(Theme.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .divider:
            Rectangle().fill(Theme.secondary.opacity(0.5)).frame(height: 1).padding(.vertical, 4)
        case .codeFence:
            EmptyView()
        case .code:
            Text((text as NSString).substring(with: p.range))
                .font(.system(size: 14, design: .monospaced))
        case .paragraph:
            inline(p)
        }
    }

    /// Строка без служебных символов, со стилями фрагментов.
    private func inline(_ p: MarkdownStyler.Paragraph, keepMarker: Bool = false) -> Text {
        let ns = text as NSString
        var hidden = IndexSet()
        if !keepMarker, let m = p.blockMarker { hidden.insert(integersIn: m.location..<NSMaxRange(m)) }
        for m in p.markers { hidden.insert(integersIn: m.location..<NSMaxRange(m)) }
        let styles = { (i: Int) in p.inlines.filter { NSLocationInRange(i, $0.range) }.map(\.style) }

        var out = AttributedString()
        var i = p.range.location
        let end = NSMaxRange(p.range)
        while i < end {
            if hidden.contains(i) { i += 1; continue }
            let current = styles(i)
            var j = i + 1
            while j < end, !hidden.contains(j), styles(j) == current { j += 1 }
            var segment = AttributedString(ns.substring(with: NSRange(location: i, length: j - i)))
            for style in current {
                switch style {
                case .bold: segment.inlinePresentationIntent = (segment.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
                case .italic: segment.inlinePresentationIntent = (segment.inlinePresentationIntent ?? []).union(.emphasized)
                case .strikethrough: segment.strikethroughStyle = .single
                case .underline: segment.underlineStyle = .single
                case .highlight: segment.backgroundColor = Color.yellow.opacity(0.35)
                case .code: segment.font = .system(size: 14, design: .monospaced)
                case .link(let url): segment.link = URL(string: url); segment.foregroundColor = Theme.accent
                }
            }
            out += segment
            i = j
        }
        return Text(out)
    }
}
