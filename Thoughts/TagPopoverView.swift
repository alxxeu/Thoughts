import SwiftUI

struct TagPopoverView: View {
    @Binding var selectedColor: CardTagColor?
    @Binding var privacyMode: CardPrivacyMode
    var onSelect: () -> Void
    /// Подсказка при первом открытии стоит сбоку от меню — в сторону, где больше места:
    /// у карточки в левой половине экрана справа, иначе слева.
    var captionOnTrailing = true
    
    private let columns = Array(repeating: GridItem(.fixed(14), spacing: 8), count: 4)
    /// Подсказка при первом открытии (слой 2): 1 — цвета, 2 — Spoiler/Lock, 0 — нет.
    @State private var coachStep = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if coachStep > 0, !captionOnTrailing { coachCaption }
            colorsAndPrivacy
            if coachStep > 0, captionOnTrailing { coachCaption }
        }
        .padding(10)
        // Размер по содержимому: после подсказки меню сужается до палитры.
        .fixedSize()
        .animation(.easeInOut(duration: 0.25), value: coachStep)
        .onAppear {
            #if DEBUG
            // Для проверки: запуск с `-alwaysTagTip YES` — подсказка при каждом открытии.
            if UserDefaults.standard.bool(forKey: "alwaysTagTip") { coachStep = 1; return }
            #endif
            guard TipsState.shared.shouldShow(.tagColors) else { return }
            TipsState.shared.markSeen(.tagColors)
            coachStep = 1
        }
    }

    /// Обводка вокруг той части, о которой сейчас подсказка.
    private func coachOutline(_ step: Int) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .shadow(color: Color.accentColor.opacity(0.6), radius: 6)
            .padding(-5)
            .opacity(coachStep == step ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: coachStep)
            .allowsHitTesting(false)
    }

    private var coachCaption: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(coachStep == 1
                 ? "Pick a color to tag this card \u{2014} or press \u{2303}1\u{2013}7 while typing (\u{2303}0 removes the tag)."
                 : "Spoiler blurs this card until you click it. Lock hides it until Touch ID. Both are for this card only.")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            // Кнопка — у внешнего края подсказки: подсказка слева — кнопка слева, справа — справа.
            HStack {
                if captionOnTrailing { Spacer() }
                Button(coachStep == 1 ? "Next" : "Done") {
                    withAnimation(.easeInOut(duration: 0.25)) { coachStep = coachStep == 1 ? 2 : 0 }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.small)
                if !captionOnTrailing { Spacer() }
            }
        }
        .frame(width: 170)
        .frame(maxHeight: .infinity, alignment: .top)
        .transition(.opacity)
    }

    /// Выбор в меню. Во время подсказки цвет не закрывает меню, а ведёт ко второму
    /// шагу — показать Spoiler/Lock, пока меню открыто.
    private func didPick(color: Bool) {
        if color, coachStep == 1 {
            withAnimation(.easeInOut(duration: 0.25)) { coachStep = 2 }
            return
        }
        coachStep = 0
        onSelect()
    }

    private var colorsAndPrivacy: some View {
        VStack(spacing: 6) {
            // 1. Сетка цветов
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(CardTagColor.allCases.prefix(3)) { tagColor in
                    TagCircleButton(tagColor: tagColor, isSelected: selectedColor == tagColor) {
                        selectedColor = tagColor
                        NotificationCenter.default.post(name: .cardTagColorWasSet, object: nil)
                        didPick(color: true)
                    }
                }

                TagCircleButton(tagColor: nil, isSelected: selectedColor == nil) {
                    selectedColor = nil
                    didPick(color: true)
                }

                ForEach(CardTagColor.allCases.suffix(4)) { tagColor in
                    TagCircleButton(tagColor: tagColor, isSelected: selectedColor == tagColor) {
                        selectedColor = tagColor
                        NotificationCenter.default.post(name: .cardTagColorWasSet, object: nil)
                        didPick(color: true)
                    }
                }
            }
            .overlay(coachOutline(1))
            
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
                    if privacyMode == .spoiler {
                        NotificationCenter.default.post(name: .cardDidBecomeSpoiler, object: nil)
                    }
                    didPick(color: false)
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
                    didPick(color: false)
                }
            }
            .overlay(coachOutline(2))
        }
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
                        .foregroundStyle(isSelected ? Color.primary.opacity(0.8) : Color.primary.opacity(0.35))
                }
            }
            .frame(width: 14, height: 14)
            .contentShape(Circle())
            .scaleEffect(isHovered ? 1.25 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            isHovered = inside
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
                    .foregroundStyle(isSelected ? Color.primary : (isHovered ? Color.primary.opacity(0.85) : Color.primary.opacity(0.45)))
                
                Text(title)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : (isHovered ? Color.primary.opacity(0.85) : Color.primary.opacity(0.55)))
            }
            .padding(.vertical, 5) // Внутренние отступы, чтобы иконка не упиралась в края
            .frame(width: 46, height: 50) // Увеличена высота кнопки (было 42)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.primary.opacity(0.15) : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = inside
            }
        }
    }
}
