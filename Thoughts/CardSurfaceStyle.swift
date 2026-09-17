import SwiftUI

/// Общий фон карточек и связанных оверлеев (Spoiler/Lock звёздное поле,
/// полноэкранный Lock Space) — .clear Liquid Glass, тонированный чёрным.
struct CardSurfaceBackground: View {
    var cornerRadius: CGFloat = 16
    /// Полноэкранный Lock Space — это прямоугольник во весь экран
    /// (cornerRadius 0), и на такой площади настоящий glassEffect рисует
    /// заметную светлую кромку-блик по верхнему краю экрана. Там нужен
    /// тот же тёмный тон, но без настоящего Liquid Glass — просто
    /// материал + тонирование.
    var usesGlassEffect: Bool = true
    /// Действует только когда usesGlassEffect == false. true — рисует
    /// .ultraThinMaterial под тоном (когда под этим слоем ещё нет
    /// никакого материала/блюра — напр. полноэкранный Lock Space). false —
    /// только сам тон без материала (напр. Spoiler/Lock оверлей карточки:
    /// настоящее стекло уже есть слоем ниже, от самой карточки — второй
    /// материал поверх первого делает поверхность непрозрачной и убивает
    /// вид Liquid Glass).
    var includesMaterial: Bool = true
    /// Плотность чёрного тона в не-стеклянных вариантах (usesGlassEffect
    /// == false) — у карточки со Spoiler/Lock и у полноэкранного Lock
    /// Space разная площадь и разный фон под ней, так что значение не
    /// общее.
    var tintOpacity: Double = 0.4
    /// Действует только когда includesMaterial == true — какой именно
    /// Material подложить под тон (напр. панели Ask AI нужен более
    /// плотный .thickMaterial, а не общий .ultraThinMaterial).
    var materialStyle: Material = .ultraThinMaterial

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(macOS 26.0, *), usesGlassEffect {
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
            } else if includesMaterial {
                // Без glassEffect нет его автоподстройки тона под фон —
                // берём фиксированное затемнение (не зависящее от
                // colorScheme), чтобы поверхность не бледнела в Light Mode.
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(materialStyle)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.black.opacity(tintOpacity))
                    )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(tintOpacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
