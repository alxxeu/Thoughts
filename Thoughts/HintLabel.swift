import SwiftUI

/// Общий таймер-контроллер всплывающей подсказки: показывается через
/// delay (0 — сразу), опционально гаснет сама через hold секунд после
/// появления. hold == nil — статичная, остаётся видимой, пока вызывающая
/// сторона сама не позовёт cancel() (например, когда внешнее условие,
/// ради которого её показали, перестало выполняться). Общий кусок для
/// всех "нежных уведомлений" в приложении — раньше каждое было отдельной
/// парой @State-булев + Task, реализованной по одному и тому же паттерну.
@Observable
final class HintTimer {
    var isVisible = false
    private var task: Task<Void, Never>?

    func show(afterDelay delay: Double = 0, holdFor hold: Double? = nil) {
        cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            // 0.35 — то же значение, что уже было у обоих существующих
            // прецедентов (showEmptyHint/showFocusHint) до этого рефактора.
            await MainActor.run { withAnimation(.easeInOut(duration: 0.35)) { isVisible = true } }
            guard let hold else { return }
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation(.easeInOut(duration: 0.35)) { isVisible = false } }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isVisible = false
    }
}

/// Общий визуальный вид всех подсказок-нудджей — единый стиль, варьируются
/// только текст/размер/прозрачность/цвет под конкретный случай. Цвет по
/// умолчанию — фиксированный белый (для подсказок поверх затемнённого
/// фона, где .primary в светлой теме читался бы как чёрный на тёмном);
/// AnyShapeStyle — чтобы можно было передать и адаптивный .primary там,
/// где подсказка лежит прямо на фоне канвы, а не поверх тонировки.
struct HintLabel: View {
    var text: String
    var fontSize: CGFloat = 11
    var color: AnyShapeStyle = AnyShapeStyle(Color.white)
    var opacity: Double = 0.4

    var body: some View {
        Text(text)
            .font(.system(size: fontSize))
            .foregroundStyle(color)
            .opacity(opacity)
            .fixedSize()
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}
