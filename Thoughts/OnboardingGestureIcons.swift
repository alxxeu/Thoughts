import SwiftUI

/// Четыре маленькие статичные иконки-подсказки — курсор в позе того же
/// жеста, который должен повторить пользователь (без анимации — только
/// один фиксированный кадр).

/// Шаг 1 — курсор растягивает пунктирный прямоугольник в карточку.
struct CreateCardGestureIcon: View {
    private let size = CGSize(width: 60, height: 42)

    var body: some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: size.width, height: size.height)
            }
            .overlay(alignment: .topLeading) {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.95))
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .offset(x: size.width - 4, y: size.height - 4)
            }
    }
}

/// Шаг 2 — карточка со сдвинутым от центра resize-хэндлом в углу.
struct MoveResizeGestureIcon: View {
    private let cardSize = CGSize(width: 46, height: 32)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.5), lineWidth: 1))
                .frame(width: cardSize.width, height: cardSize.height)

            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.9))
                .padding(4)
                .background(Circle().fill(Color.primary.opacity(0.18)))
                .offset(x: cardSize.width / 2 - 2, y: cardSize.height / 2 - 2)
        }
        .frame(width: cardSize.width + 24, height: cardSize.height + 12)
    }
}

/// Шаг 3 — карточка с выбранной цветной точкой в углу.
struct TagColorGestureIcon: View {
    private let cardSize = CGSize(width: 48, height: 34)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.4), lineWidth: 1))
                .frame(width: cardSize.width, height: cardSize.height)

            Circle()
                .fill(Color.red)
                .frame(width: 11, height: 11)
                .offset(x: 4, y: -4)
        }
        .frame(width: cardSize.width + 12, height: cardSize.height + 12)
    }
}

/// Шаг 4 — карточка с размытыми "строчками" текста и иконкой eye.slash —
/// то же визуальное решение, что у настоящего Spoiler-оверлея карточки.
struct SpoilerGestureIcon: View {
    private let cardSize = CGSize(width: 52, height: 36)

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<3, id: \.self) { row in
                    Capsule()
                        .fill(Color.primary.opacity(0.5))
                        .frame(width: cardSize.width - CGFloat(row * 10) - 14, height: 4)
                }
            }
            .padding(6)
            .frame(width: cardSize.width, height: cardSize.height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.35), lineWidth: 1))
            .blur(radius: 4)

            Image(systemName: "eye.slash.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.9))
        }
        .frame(width: cardSize.width + 12, height: cardSize.height + 12)
    }
}
