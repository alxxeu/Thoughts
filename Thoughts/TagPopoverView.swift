import SwiftUI

struct TagPopoverView: View {
    @Binding var selectedColor: CardTagColor?
    var onSelect: () -> Void
    
    // 1. Четкая геометрия: 4 колонки строго по 14 pt с равными отступами 8 pt
    private let columns = Array(repeating: GridItem(.fixed(14), spacing: 8), count: 4)
    private let allColors: [CardTagColor] = [.red, .orange, .yellow, .green, .blue, .indigo, .purple]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            // Верхний ряд: Красный, Оранжевый, Желтый + Отмена
            ForEach(allColors.prefix(3)) { tagColor in
                TagCircleButton(
                    tagColor: tagColor,
                    isSelected: selectedColor == tagColor
                ) {
                    selectedColor = tagColor
                    onSelect()
                }
            }
            
            TagCircleButton(
                tagColor: nil,
                isSelected: selectedColor == nil
            ) {
                selectedColor = nil
                onSelect()
            }
            
            // Нижний ряд: Зеленый, Синий, Индиго, Фиолетовый
            ForEach(allColors.suffix(4)) { tagColor in
                TagCircleButton(
                    tagColor: tagColor,
                    isSelected: selectedColor == tagColor
                ) {
                    selectedColor = tagColor
                    onSelect()
                }
            }
        }
        .padding(8)
    }
}

private struct TagCircleButton: View {
    let tagColor: CardTagColor?
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if let tagColor = tagColor {
                    Circle()
                        .fill(tagColor.color)
                        .frame(width: 14, height: 14)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 6, height: 6) // Точка пропорционально уменьшена до 6 pt
                    }
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 14, height: 14)
                    
                    Image(systemName: "nosign")
                        .font(.system(size: 13, weight: .bold)) // Уменьшена, чтобы не выходить за 14 pt
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .white.opacity(0.35))
                }
            }
            .frame(width: 14, height: 14) // Жестко ограничиваем фрейм контейнера
            .contentShape(Circle())
            .scaleEffect(isHovered ? 1.25 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            isHovered = inside
            if inside {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
    }
}
