import AppKit
import Testing
@testable import Thoughts

@MainActor
struct MarkdownBlockDecoratorTests {
    /// Настоящая вёрстка TextKit вне окна — как в редакторе карточки.
    private func decorator(_ text: String) -> MarkdownBlockDecorator {
        let storage = NSTextStorage(string: text)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 244, height: 1e6))
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        MarkdownRenderer.style(storage, typography: CardTypography(font: .systemFont(ofSize: 15), color: .white))
        layoutManager.ensureLayout(for: container)
        return MarkdownBlockDecorator(
            layoutManager: layoutManager, textContainer: container, textStorage: storage,
            origin: .zero, textColor: .white, lineColor: .gray, copiedBlockLocation: nil
        )
    }

    @Test func clickOnCheckboxToggles() {
        let empty = decorator("- [ ] buy")
        let line = empty.layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        guard case .toggleTask(let range, let replacement)? = empty.hit(at: NSPoint(x: 6, y: line.midY)) else {
            Issue.record("no checkbox hit")
            return
        }
        #expect(range == NSRange(location: 3, length: 1))
        #expect(replacement == "x")

        let done = decorator("- [x] buy")
        guard case .toggleTask(_, let back)? = done.hit(at: NSPoint(x: 6, y: line.midY)) else {
            Issue.record("no checkbox hit")
            return
        }
        #expect(back == " ")
        // Клик по тексту пункта — не по квадратику.
        #expect(empty.hit(at: NSPoint(x: 120, y: line.midY)) == nil)
    }

    @Test func copyButtonCopiesCodeWithoutFences() {
        let code = decorator("```\nlet x = 1\nprint(x)\n```")
        // Значок — в правом верхнем углу поля блока.
        guard case .copyCode(_, let text)? = code.hit(at: NSPoint(x: 244 + 6 - 15, y: 10)) else {
            Issue.record("no copy hit")
            return
        }
        #expect(text == "let x = 1\nprint(x)")
    }
}

extension MarkdownBlockDecorator.Hit: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.copyCode(a, t1), .copyCode(b, t2)): return a == b && t1 == t2
        case let (.toggleTask(a, r1), .toggleTask(b, r2)): return a == b && r1 == r2
        default: return false
        }
    }
}
