import SwiftUI

struct StarFieldOverlayView: View {
    let mode: CardPrivacyMode
    let onTap: () -> Void

    var body: some View {
        ZStack {
            // Liquid Glass + тонкий чёрный тон поверх — тот же, что у
            // обычных карточек. См. CardSurfaceStyle.swift.
            CardSurfaceBackground()

            // 3. Анимированное звездное поле с мягкой маской затухания по краям
            StarFieldCanvas()
                .mask {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black)
                        .padding(10)      // Отступ от края карточки, где начинается затухание
                        .blur(radius: 8)  // Плавный градиент угасания
                }
                .clipShape(RoundedRectangle(cornerRadius: 16)) // Жесткая обрезка по скруглению
            
            // 4. Иконка замка для режима Lock
            if mode == .lock {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
        }
        .contentShape(Rectangle())
        .modifier(DefaultPointerStyleModifier())
        .onTapGesture {
            onTap()
        }
    }
}

/// .pointerStyle доступен только с macOS 15 (минимум приложения — 14).
private struct DefaultPointerStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.default)
        } else {
            content
        }
    }
}

/// Не private — переиспользуется и в SpaceLockOverlayView (полноэкранная
/// блокировка Space), не только в оверлее заметки.
struct StarFieldCanvas: View {
    /// "Паспорт" звезды — то, что зависит только от её номера, а не от
    /// времени: стартовая точка, скорость, размер, фаза мерцания, базовая
    /// яркость. Раньше пересчитывалось заново на каждом кадре (до 120
    /// раз/сек на ProMotion) для каждой видимой Spoiler/Lock карточки —
    /// это чистые константы, посчитать нужно один раз и переиспользовать.
    private struct StarIdentity {
        let xFrac: Double
        let yFrac: Double
        let speed: Double
        let starSize: Double
        let twinklePhase: Double
        let baseOpacity: Double
    }

    private static let maxStarCount = 300

    /// Общий на все карточки/процесс массив — детерминированная функция от
    /// индекса, так что карточкам с одинаковым числом звёзд не нужно иметь
    /// каждой свою копию.
    private static let starIdentities: [StarIdentity] = (0..<maxStarCount).map { i in
        let seed1 = sin(Double(i) * 12.9898 + 1.0) * 43758.5453
        let seed2 = cos(Double(i) * 78.2330 + 2.0) * 43758.5453
        let seed3 = sin(Double(i) * 45.1640 + 3.0) * 12345.6789
        let seed4 = cos(Double(i) * 91.8270 + 4.0) * 65432.1098
        let seed5 = sin(Double(i) * 33.4560 + 5.0) * 98765.4321

        let xFrac = seed1 - floor(seed1)
        let yFrac = seed2 - floor(seed2)
        let speed = 0.3 + (seed3 - floor(seed3)) * 0.5
        let sizeFrac = seed4 - floor(seed4)
        let twinklePhase = (seed5 - floor(seed5)) * .pi * 2
        let starSize = 1.0 + sizeFrac * 1.0
        let baseOpacity = 0.35 + (seed2 - floor(seed2)) * 0.45

        return StarIdentity(
            xFrac: xFrac,
            yFrac: yFrac,
            speed: speed,
            starSize: starSize,
            twinklePhase: twinklePhase,
            baseOpacity: baseOpacity
        )
    }

    var body: some View {
        // 24 кадра/сек вместо частоты экрана (до 120 Гц) — движение
        // медленное, разницы на глаз нет, а работы в 3-5 раз меньше.
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate

                // Фиксированная плотность: 1 звезда примерно на каждые 1600 px²,
                // с верхним пределом — на очень крупных заблокированных
                // карточках (можно растянуть почти на весь холст) иначе
                // получались бы тысячи звёзд без заметной визуальной разницы.
                let area = size.width * size.height
                let starCount = min(Self.maxStarCount, max(6, Int(area / 1600)))

                // Группируем звёзды по округлённой прозрачности и заливаем
                // каждую группу одним вызовом — вместо отдельного
                // context.fill() на каждую из (до 300) звёзд на каждый
                // кадр, теперь не больше ~9 вызовов (число шагов яркости).
                // context.fill — это смена состояния графического контекста,
                // а не просто геометрия, так что именно число вызовов, а не
                // число точек в path, определяет стоимость кадра.
                var pathsByOpacityStep: [Int: Path] = [:]

                for i in 0..<starCount {
                    let star = Self.starIdentities[i]

                    // Только это по-настоящему меняется от кадра к кадру —
                    // текущая позиция и текущая яркость, выведенные из
                    // фиксированного "паспорта" звезды выше и текущего now.
                    let yOffset = sin(now * star.speed * 1.8 + star.xFrac * 10) * 7.0
                    let xOffset = cos(now * star.speed * 1.2 + star.yFrac * 10) * 4.0

                    let xPos = star.xFrac * size.width + xOffset
                    let rawY = star.yFrac * size.height + yOffset
                    let yPos = rawY < 0 ? rawY + size.height : rawY.truncatingRemainder(dividingBy: size.height)

                    let twinkle = sin(now * star.speed * 2.5 + star.twinklePhase) * 0.25
                    let finalOpacity = max(0.15, min(0.95, star.baseOpacity + twinkle))

                    let rect = CGRect(x: xPos, y: yPos, width: star.starSize, height: star.starSize)
                    let opacityStep = Int((finalOpacity * 10).rounded())
                    pathsByOpacityStep[opacityStep, default: Path()].addEllipse(in: rect)
                }

                // Фикс. белый — фон StarFieldOverlayView/SpaceLockOverlayView
                // больше не переключается в светлый в Light Mode (см.
                // CardSurfaceStyle), так что звёзды должны оставаться
                // светлыми в обеих темах, а не следовать .primary.
                for (opacityStep, path) in pathsByOpacityStep {
                    context.opacity = Double(opacityStep) / 10
                    context.fill(path, with: .color(.white))
                }
            }
        }
    }
}
