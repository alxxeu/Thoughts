import SwiftUI

struct TagPopoverView: View {
    @Binding var selectedColor: CardTagColor?
    @Binding var privacyMode: CardPrivacyMode
    var onSelect: () -> Void
    
    private let columns = Array(repeating: GridItem(.fixed(14), spacing: 8), count: 4)
    private let allColors: [CardTagColor] = [.red, .orange, .yellow, .green, .blue, .indigo, .purple]
    
    var body: some View {
        VStack(spacing: 6) {
            // 1. Сетка цветов
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(allColors.prefix(3)) { tagColor in
                    TagCircleButton(tagColor: tagColor, isSelected: selectedColor == tagColor) {
                        selectedColor = tagColor
                        onSelect()
                    }
                }
                
                TagCircleButton(tagColor: nil, isSelected: selectedColor == nil) {
                    selectedColor = nil
                    onSelect()
                }
                
                ForEach(allColors.suffix(4)) { tagColor in
                    TagCircleButton(tagColor: tagColor, isSelected: selectedColor == tagColor) {
                        selectedColor = tagColor
                        onSelect()
                    }
                }
            }
            
            Divider()
                .opacity(0.3)
            
            // 2. Кнопки режимов приватности
            HStack(alignment: .bottom, spacing: 2) {
                // SPOILER
                PrivacyActionButton(
                    title: "Spoiler",
                    iconName: "sparkles.square.filled.on.square",
                    iconSize: 18,
                    isSelected: privacyMode == .spoiler
                ) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        privacyMode = (privacyMode == .spoiler) ? .none : .spoiler
                    }
                    onSelect()
                }
                
                // LOCK
                PrivacyActionButton(
                    title: "Lock",
                    iconName: "lock.square.fill",
                    iconSize: 20,
                    isSelected: privacyMode == .lock
                ) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        privacyMode = (privacyMode == .lock) ? .none : .lock
                    }
                    onSelect()
                }
            }
        }
        .padding(10)
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
                            .frame(width: 6, height: 6)
                    }
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 14, height: 14)
                    
                    Image(systemName: "nosign")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .white.opacity(0.35))
                }
            }
            .frame(width: 14, height: 14)
            .contentShape(Circle())
            .scaleEffect(isHovered ? 1.25 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            isHovered = inside
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
    }
}

private struct PrivacyActionButton: View {
    let title: String
    let iconName: String
    let iconSize: CGFloat
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: iconSize))
                    .frame(height: 20)
                    .foregroundStyle(isSelected ? .white : (isHovered ? .white.opacity(0.85) : .white.opacity(0.45)))
                
                Text(title)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : (isHovered ? .white.opacity(0.85) : .white.opacity(0.55)))
            }
            .padding(.vertical, 5) // Внутренние отступы, чтобы иконка не упиралась в края
            .frame(width: 46, height: 50) // Увеличена высота кнопки (было 42)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.15) : (isHovered ? Color.white.opacity(0.08) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = inside
            }
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}
