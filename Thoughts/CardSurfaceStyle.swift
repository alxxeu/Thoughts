import SwiftUI

/// Общий фон карточек и связанных оверлеев (Spoiler/Lock звёздное поле,
/// полноэкранный Lock Space) — .clear Liquid Glass, тонированный чёрным.
struct CardSurfaceBackground: View {
    var cornerRadius: CGFloat = 16

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                          AnyShapeStyle(.ultraThinMaterial.opacity(0.6)))
                          
                    .blendMode(colorScheme == .dark ? .multiply : .multiply)
                    .glassEffect(
                        colorScheme == .dark
                        ? .clear.tint(Color.black.opacity(0.05))
                        : .clear.tint(Color.black.opacity(0.2)),
                        in: .rect(cornerRadius: cornerRadius)
                    )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
