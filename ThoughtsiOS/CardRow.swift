import LocalAuthentication
import SwiftUI

/// Сессия: Lock-карточки открываются Face ID один раз, до ухода приложения в фон (Р7).
@Observable
final class LockSession {
    var isUnlocked = false

    func unlock() async -> Bool {
        if isUnlocked { return true }
        let context = LAContext()
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open locked cards")) ?? false
        isUnlocked = ok
        return ok
    }
}

/// Карточка в ленте: стекло, превью до 10 строк с мягким затуханием, точка тега
/// справа сверху, Spoiler — звёзды поверх, Lock — замок.
struct CardRow: View {
    let card: Card
    let isRevealed: Bool
    var onReveal: () -> Void
    var onToggleTask: (MarkdownStyler.Paragraph) -> Void

    private static let lineHeight: CGFloat = 20
    private static let maxLines: CGFloat = 10
    private static let fade: CGFloat = 15 // как маска CardView на Mac
    @State private var contentHeight: CGFloat = 0

    private var isHidden: Bool { card.privacyMode != .none && !isRevealed }
    private var maxHeight: CGFloat { Self.lineHeight * Self.maxLines }

    var body: some View {
        ZStack {
            if card.privacyMode == .lock && isHidden {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 32)
            } else {
                preview.opacity(isHidden ? 0 : 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            ZStack {
                // Стекло с тёмным оттенком: чистое .clear на тёмном фоне выходит слишком светлым.
                Color.clear.glassEffect(.clear.tint(.black.opacity(0.5)), in: .rect(cornerRadius: Theme.cardRadius))
                if isHidden {
                    RoundedRectangle(cornerRadius: Theme.cardRadius).fill(.black.opacity(0.2))
                    StarFieldCanvas()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let tag = card.tagColor {
                Circle().fill(tag.color).frame(width: 8, height: 8).padding(10)
            }
        }
        .contentShape(.rect(cornerRadius: Theme.cardRadius))
        .simultaneousGesture(TapGesture().onEnded { if isHidden { onReveal() } }, isEnabled: isHidden)
    }

    /// Превью: естественная высота, обрезка на 10 строках, затухание — только если не влезло.
    private var preview: some View {
        MarkdownPreview(text: card.text, onToggleTask: isHidden ? nil : onToggleTask)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .frame(maxHeight: maxHeight, alignment: .top)
            .clipped()
            .mask {
                if contentHeight > maxHeight {
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 1 - Self.fade / maxHeight),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                } else {
                    Color.black
                }
            }
    }
}
