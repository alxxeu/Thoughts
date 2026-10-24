import SwiftUI

/// Слой 2: подсказка внизу доски в момент первого использования — иконка, одна
/// фраза, «Got it» (Return) и, где нужно, кнопка действия.
struct TipToastView: View {
    let tip: Tip
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Self.symbol(tip))
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            Text(Self.text(tip))
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380, alignment: .leading)
            if tip == .spaceLock {
                Button("Open Security") {
                    SettingsNavigation.shared.open(.security)
                    TipsState.shared.noteAction(for: .spaceLock)
                }
            }
            Button("Got it", action: onDismiss)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(CardSurfaceBackground(cornerRadius: 16, usesGlassEffect: false, tintOpacity: 0.22))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
    }

    static func text(_ tip: Tip) -> String {
        switch tip {
        case .spaceSwitch:
            return "Switch Spaces with \u{2325}1\u{2013}9 or \u{2325}\u{2190} \u{2325}\u{2192}. Hold \u{2325} and press Tab to see all of them."
        case .spaceBar:
            return "The bar at the top is your Space: click its name to rename it. The icons next to it ask AI about the Space, tidy the cards, clear the Space, or lock it with a passcode \u{2014} hover the bar and click the gear to hide icons or change their order."
        case .spaceLock:
            return "Keep a Space private: turn on a passcode in Settings \u{2192} Security, then press \u{2318}L to lock the whole Space."
        case .focusMode:
            return "Long card? Press \u{2318}F to focus on it: everything else fades away so you can write without distractions. Ask AI appears below the card to summarize it, rewrite it or ask about it. Esc, \u{2318}F again or a click outside brings the board back."
        case .askAI:
            return "Ask anything about this Space \u{2014} the answer arrives as a new card. Choose the AI provider in Settings \u{2192} AI."
        case .tagColors:
            return ""
        }
    }

    static func symbol(_ tip: Tip) -> String {
        switch tip {
        case .spaceSwitch: return "square.stack.3d.up"
        case .spaceBar: return "capsule"
        case .spaceLock: return "lock.shield"
        case .focusMode: return "scope"
        case .askAI: return "sparkle"
        case .tagColors: return "circle.fill"
        }
    }
}

/// Слой подсказок внизу доски — отдельный вид, чтобы не утяжелять ContentView.body.
struct TipToastLayer: View {
    var isHidden: Bool
    private let state = TipsState.shared

    var body: some View {
        ZStack {
            if let tip = state.currentToast, !isHidden {
                TipToastView(tip: tip) {
                    withAnimation(.easeInOut(duration: 0.25)) { state.dismissToast() }
                }
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.currentToast)
    }
}
