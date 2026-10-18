import SwiftUI

/// Звёздный блюр Spoiler/Lock. Общий для Mac (оверлей карточки, блокировка
/// Space) и iPhone (карточка в ленте).
struct StarFieldCanvas: View {
    /// "Паспорт" звезды — то, что зависит только от её номера, а не от
    /// времени: стартовая точка, скорость, размер, фаза мерцания, базовая
    /// яркость. Раньше пересчитывалось заново на каждом кадре (до 120
    /// раз/сек на ProMotion) для каждой видимой Spoiler/Lock карточки —
    /// это чистые константы, посчитать нужно один раз и переиспользовать.
    struct StarIdentity {
        let xFrac: Double
        let yFrac: Double
        let speed: Double
        let starSize: Double
        let twinklePhase: Double
        let baseOpacity: Double
    }

    private static let maxStarCount = 300
    /// Общее поле — сетка клеток 40×40 pt (1 звезда на 1600 pt², как у поля карточки);
    /// у каждой клетки звезда из таблицы по хешу клетки. Поле бесконечное, без повторов.
    static let cell: CGFloat = 40
    static let tableCount = 625

    /// Остановить анимацию (звёзды замирают): карточка не видна — лента iPhone
    /// держит собранными страницы всех Spaces, и невидимые звёзды иначе
    /// перерисовывались бы постоянно, занимая главный поток.
    var isPaused = false

    /// Общий на все карточки/процесс массив — детерминированная функция от
    /// индекса, так что карточкам с одинаковым числом звёзд не нужно иметь
    /// каждой свою копию.
    static let starIdentities: [StarIdentity] = (0..<tableCount).map { i in
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

    /// Положение этого поля на общем холсте (карточка в координатах окна). Тогда звёзды
    /// берутся из одного виртуального поля на весь холст: у соседних карточек рисунок
    /// разный и продолжается на стыках, а при перетаскивании звёзды скользят под
    /// карточкой, как в пустоте. nil — своё поле от нуля (Space Lock на весь экран).
    var origin: CGPoint? = nil

    var body: some View {
        // 24 кадра/сек вместо частоты экрана (до 120 Гц) — движение
        // медленное, разницы на глаз нет, а работы в 3-5 раз меньше.
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: isPaused)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate

                // Фиксированная плотность: 1 звезда примерно на каждые 1600 px²,
                // с верхним пределом — на очень крупных заблокированных
                // карточках (можно растянуть почти на весь холст) иначе
                // получались бы тысячи звёзд без заметной визуальной разницы.
                let area = size.width * size.height
                let starCount = min(Self.maxStarCount, max(6, Int(area / 1600)))
                let isShared = origin != nil
                let o = origin ?? .zero
                let cell = Self.cell
                let cx = isShared ? Int(floor((o.x - 8) / cell))...Int(floor((o.x + size.width + 8) / cell)) : 0...0
                let cy = isShared ? Int(floor((o.y - 10) / cell))...Int(floor((o.y + size.height + 10) / cell)) : 0...0

                // Группируем звёзды по округлённой прозрачности и заливаем
                // каждую группу одним вызовом — вместо отдельного
                // context.fill() на каждую из (до 300) звёзд на каждый
                // кадр, теперь не больше ~9 вызовов (число шагов яркости).
                // context.fill — это смена состояния графического контекста,
                // а не просто геометрия, так что именно число вызовов, а не
                // число точек в path, определяет стоимость кадра.
                var pathsByOpacityStep: [Int: Path] = [:]

                if isShared {
                    for gx in cx {
                        for gy in cy {
                            let hash = (gx &* 73856093) ^ (gy &* 19349663)
                            let star = Self.starIdentities[abs(hash % Self.tableCount)]
                            let xPos = (CGFloat(gx) + star.xFrac) * cell - o.x + cos(now * star.speed * 1.2 + star.yFrac * 10) * 4.0
                            let yPos = (CGFloat(gy) + star.yFrac) * cell - o.y + sin(now * star.speed * 1.8 + star.xFrac * 10) * 7.0
                            guard xPos > -8, xPos < size.width + 8, yPos > -10, yPos < size.height + 10 else { continue }
                            let twinkle = sin(now * star.speed * 2.5 + star.twinklePhase) * 0.25
                            let opacityStep = Int((max(0.15, min(0.95, star.baseOpacity + twinkle)) * 10).rounded())
                            pathsByOpacityStep[opacityStep, default: Path()]
                                .addEllipse(in: CGRect(x: xPos, y: yPos, width: star.starSize, height: star.starSize))
                        }
                    }
                }

                for i in 0..<(isShared ? 0 : starCount) {
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
                    let opacityStep = Int((max(0.15, min(0.95, star.baseOpacity + twinkle)) * 10).rounded())
                    let rect = CGRect(x: xPos, y: yPos, width: star.starSize, height: star.starSize)
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
