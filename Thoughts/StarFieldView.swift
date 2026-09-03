import SwiftUI

struct StarFieldOverlayView: View {
    let mode: CardPrivacyMode
    let onTap: () -> Void
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.1))
                .glassEffect(in: .rect(cornerRadius: 16.0))
            
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
        .pointerStyle(.default)
        .onTapGesture {
            onTap()
        }
    }
}

private struct StarFieldCanvas: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                
                // Фиксированная плотность: 1 звезда примерно на каждые 1600 px²
                let area = size.width * size.height
                let starCount = max(6, Int(area / 1600))
                
                for i in 0..<starCount {
                    // Независимые детерминированные значения для каждого параметра
                    let seed1 = sin(Double(i) * 12.9898 + 1.0) * 43758.5453
                    let seed2 = cos(Double(i) * 78.2330 + 2.0) * 43758.5453
                    let seed3 = sin(Double(i) * 45.1640 + 3.0) * 12345.6789
                    let seed4 = cos(Double(i) * 91.8270 + 4.0) * 65432.1098
                    let seed5 = sin(Double(i) * 33.4560 + 5.0) * 98765.4321
                    
                    let xFrac = seed1 - floor(seed1)
                    let yFrac = seed2 - floor(seed2)
                    let speed = 0.3 + (seed3 - floor(seed3)) * 0.5   // Динамичная скорость
                    let sizeFrac = seed4 - floor(seed4)              // Отдельный seed: размер независим от X/Y
                    let twinklePhase = (seed5 - floor(seed5)) * .pi * 2
                    
                    // Однородный размер звёзд по всей площади (от 1.0 до 2.0 pt)
                    let starSize = 1.0 + sizeFrac * 1.0
                    
                    // Динамичное движение по X и Y
                    let yOffset = sin(now * speed * 1.8 + xFrac * 10) * 7.0
                    let xOffset = cos(now * speed * 1.2 + yFrac * 10) * 4.0
                    
                    let xPos = xFrac * size.width + xOffset
                    let rawY = yFrac * size.height + yOffset
                    let yPos = rawY < 0 ? rawY + size.height : rawY.truncatingRemainder(dividingBy: size.height)
                    
                    // Живое мерцание прозрачности
                    let baseOpacity = 0.35 + (seed2 - floor(seed2)) * 0.45
                    let twinkle = sin(now * speed * 2.5 + twinklePhase) * 0.25
                    let finalOpacity = max(0.15, min(0.95, baseOpacity + twinkle))
                    
                    let rect = CGRect(
                        x: xPos,
                        y: yPos,
                        width: starSize,
                        height: starSize
                    )
                    
                    let path = Path(ellipseIn: rect)
                    context.opacity = finalOpacity
                    context.fill(path, with: .color(.white))
                }
            }
        }
    }
}
