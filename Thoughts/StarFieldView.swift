import SwiftUI

struct StarFieldOverlayView: View {
    let mode: CardPrivacyMode
    let onTap: () -> Void

    var body: some View {
        ZStack {
            // Настоящий Liquid Glass уже есть на самой карточке под этим
            // оверлеем (см. CardView) — второй слой материала поверх
            // первого делает карточку непрозрачной. Тут только доп.
            // затемнение, без материала. См. CardSurfaceStyle.swift.
            CardSurfaceBackground(usesGlassEffect: false, includesMaterial: false, tintOpacity: 0.2)

            // 3. Анимированное звездное поле с мягкой маской затухания по краям
            // Звёзды — из общего поля холста по положению карточки (см. StarFieldCanvas.origin).
            GeometryReader { proxy in
                StarFieldCanvas(origin: proxy.frame(in: .named("canvas")).origin)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
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

