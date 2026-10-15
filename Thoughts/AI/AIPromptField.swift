import SwiftUI

/// Поле вопроса к AI на тёмных панелях — Ask AI по Space (SpaceToolbar) и
/// под карточкой в Focus Mode (CardAskAIPanel): плейсхолдер, выбор
/// провайдера слева внизу, отправка со спиннером справа внизу. У панели
/// из контекстного меню (AskAIPopover) — системный стиль, она своя.
struct AIPromptField: View {
    @Binding var text: String
    var placeholder: String
    var shouldFocus: Bool
    var isBusy: Bool
    var height: CGFloat
    var sendIconSize: CGFloat = 20
    var onSend: () -> Void

    private var canSend: Bool {
        !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        AIPromptTextView(text: $text, shouldFocus: shouldFocus, onSend: onSend)
            .frame(height: height)
            // NSTextView не даёт placeholder "из коробки" — просто текст
            // поверх, скрытый, как только начали печатать. Отступы подобраны
            // под textContainerInset (6) + lineFragmentPadding NSTextView (5).
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .padding(.leading, 11)
                        .padding(.top, 6)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                AIProviderMenu()
                    .padding(5)
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: sendIconSize))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .disabled(!canSend)
                }
                .padding(5)
            }
    }
}
