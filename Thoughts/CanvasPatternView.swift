import SwiftUI

/// Декоративный паттерн на фоне канвы (Settings → Appearance → Background).
/// Лежит под карточками и жестом создания карточки, клики не перехватывает.
/// Цвет — .primary с прозрачностью: сам фон окна (VisualEffectBlur) светлый
/// или тёмный вслед за темой, и паттерн должен читаться на обоих.
struct CanvasPatternView: View {
    var pattern: CanvasPattern
    var opacity: Double

    var body: some View {
        if pattern.kind != .none {
            Canvas { context, size in
                context.stroke(
                    Self.path(for: pattern, in: size),
                    with: .color(.primary.opacity(opacity)),
                    lineWidth: pattern.lineWidth
                )
                if pattern.kind == .dots {
                    context.fill(Self.dotsPath(for: pattern, in: size), with: .color(.primary.opacity(opacity)))
                }
            }
            .allowsHitTesting(false)
        }
    }

    private static func path(for pattern: CanvasPattern, in size: CGSize) -> Path {
        let step = max(pattern.spacing, 4)
        var path = Path()

        switch pattern.kind {
        case .none, .dots:
            break

        case .grid:
            var x = step
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            fallthrough

        case .lines:
            var y = step
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }

        case .crosses:
            let arm = pattern.dotSize / 2
            forEachNode(step: step, in: size) { point in
                path.move(to: CGPoint(x: point.x - arm, y: point.y))
                path.addLine(to: CGPoint(x: point.x + arm, y: point.y))
                path.move(to: CGPoint(x: point.x, y: point.y - arm))
                path.addLine(to: CGPoint(x: point.x, y: point.y + arm))
            }

        case .diagonal:
            // Линии под 45° от левого края и дальше вправо на всю ширину +
            // высоту — так покрывается весь прямоугольник без пропусков в углах.
            var offset = -size.height
            while offset < size.width {
                path.move(to: CGPoint(x: offset, y: size.height))
                path.addLine(to: CGPoint(x: offset + size.height, y: 0))
                offset += step
            }
        }

        return path
    }

    private static func dotsPath(for pattern: CanvasPattern, in size: CGSize) -> Path {
        let radius = pattern.dotSize / 2
        var path = Path()
        forEachNode(step: max(pattern.spacing, 4), in: size) { point in
            path.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
        return path
    }

    private static func forEachNode(step: CGFloat, in size: CGSize, _ body: (CGPoint) -> Void) {
        var y = step
        while y < size.height {
            var x = step
            while x < size.width {
                body(CGPoint(x: x, y: y))
                x += step
            }
            y += step
        }
    }
}
