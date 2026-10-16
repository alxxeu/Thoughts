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

/// Copy / Share / Delete карточки — меню долгого нажатия в ленте и «…» редактора.
struct CardActions: View {
    let card: Card
    var onDelete: () -> Void

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = card.text }
        ShareLink(item: card.text) { Label("Share", systemImage: "square.and.arrow.up") }
        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
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
            // Скрытая карточка сохраняет свой размер: текст разложен, но невидим.
            preview.opacity(isHidden ? 0 : 1).accessibilityHidden(isHidden)
            if card.privacyMode == .lock && isHidden {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.text)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        // Длинная карточка: текст гаснет маской прямо у нижнего края, без отступа под ним.
        .padding(.bottom, contentHeight > maxHeight ? 0 : 16)
        .background {
            ZStack {
                // Стекло с тёмным оттенком: чистое .clear на тёмном фоне выходит слишком светлым.
                // На устройстве оттенок ложится гуще, чем в симуляторе (0.5 там — чёрный).
                Color.clear.glassEffect(.clear.tint(.black.opacity(0.2)), in: .rect(cornerRadius: Theme.cardRadius))
                if isHidden {
                    RoundedRectangle(cornerRadius: Theme.cardRadius).fill(.black.opacity(0.2))
                    StarFieldCanvas()
                        .mask { Self.edgeFade } // звёзды гаснут у верхнего и нижнего края
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

    /// Маска мягкого края сверху и снизу — та же высота затухания, что у длинного текста.
    private static var edgeFade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: fade)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: fade)
        }
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
