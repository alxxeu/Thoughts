import SwiftUI

/// Общий "плавающий" контейнер одного шага онбординга — небольшая панель
/// поверх живой канвы, а не блокирующее модальное окно (в отличие от
/// старого 400×420 карусельного дизайна). Декоративная часть (фон, иконка,
/// текст) специально .allowsHitTesting(false) — жестовые шаги буквально
/// требуют, чтобы драг долетал до настоящей канвы под панелью.
///
/// Важно: .allowsHitTesting(false) применён ТОЛЬКО к декоративным листьям
/// и к фону по отдельности — НЕ к общему контейнеру, в котором лежат
/// Next/Skip. На практике "потомок переопределяет allowsHitTesting предка"
/// (как раньше было тут написано) не сработало надёжно — кнопка Next
/// физически не нажималась на информационных шагах. Поэтому кнопки просто
/// никогда не оказываются внутри поддерева с отключённым hit-testing.
struct OnboardingCoachmarkView<Icon: View>: View {
    @ViewBuilder var icon: () -> Icon
    var title: String
    var description: String
    var hint: String?
    var showsSkip: Bool
    var onSkip: () -> Void
    var primaryButtonTitle: String?
    var onPrimary: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            icon()
                .frame(height: 60)
                .allowsHitTesting(false)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .allowsHitTesting(false)

            if let hint {
                Text(hint)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
                    .allowsHitTesting(false)
            }

            if let primaryButtonTitle, let onPrimary {
                Button(action: onPrimary) {
                    Text(primaryButtonTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.9))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.primary.opacity(0.14)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .frame(width: 300)
        .background(
            CardSurfaceBackground(cornerRadius: 20, usesGlassEffect: false, tintOpacity: 0.18, materialStyle: .thickMaterial)
                .allowsHitTesting(false)
        )
        .overlay(alignment: .topTrailing) {
            if showsSkip {
                Button("Skip tour", action: onSkip)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.5))
                    .padding(12)
            }
        }
    }
}
