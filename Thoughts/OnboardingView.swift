import SwiftUI

/// Показывается один раз при первом запуске — короткий тур по уже
/// реализованным функциям (не по гипотетическим), тот же визуальный язык,
/// что и у SpaceLockOverlayView (StarFieldCanvas + glass/material фон).
/// Флаг завершения — в UserDefaults, тот же стиль ключей, что в
/// SecuritySettings ("namespace.name").
enum OnboardingState {
    private static let hasCompletedKey = "onboarding.hasCompletedTour"

    static var hasCompletedTour: Bool {
        get { UserDefaults.standard.bool(forKey: hasCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedKey) }
    }
}

private struct OnboardingPage {
    let symbol: String
    let title: String
    let description: String
    let hint: String?

    init(symbol: String, title: String, description: String, hint: String? = nil) {
        self.symbol = symbol
        self.title = title
        self.description = description
        self.hint = hint
    }
}

/// Порядок и формулировки — по реальным жестам/шорткатам приложения, не
/// маркетинговый текст. Если фича поменяется, страницы стоит поправить
/// вместе с ней, а не оставлять как заглушку.
private let onboardingPages: [OnboardingPage] = [
    OnboardingPage(
        symbol: "sparkles",
        title: "Welcome to Thoughts",
        description: "A free-form canvas for scattered ideas — no folders, no lists, just space to think."
    ),
    OnboardingPage(
        symbol: "hand.draw",
        title: "Create a Card",
        description: "Click and drag anywhere on the empty canvas to create a card. Drag it to move, drag its corner to resize, click the \u{2715} to delete."
    ),
    OnboardingPage(
        symbol: "tag.fill",
        title: "Color Tags",
        description: "Click the dot in a card's corner and pick a color to tag it — handy for grouping related cards at a glance."
    ),
    OnboardingPage(
        symbol: "eye.slash.fill",
        title: "Card Privacy",
        description: "From that same dot, blur a card's contents (Spoiler) or hide it completely (Lock) behind your passcode."
    ),
    OnboardingPage(
        symbol: "square.grid.3x3",
        title: "Multiple Spaces",
        description: "Click the name at the top to rename the current Space. Switch between Spaces anytime.",
        hint: "\u{2325}1 \u{2013} \u{2325}9"
    ),
    OnboardingPage(
        symbol: "lock.shield",
        title: "Lock an Entire Space",
        description: "Turn on Passcode in Settings \u{2192} Security to protect any Space, then lock the current one instantly.",
        hint: "\u{2318}L"
    ),
    OnboardingPage(
        symbol: "magnifyingglass",
        title: "Find Anything Instantly",
        description: "Your cards are indexed in system Spotlight — search their text from anywhere on your Mac.",
        hint: "\u{2318}Space"
    )
]

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var pageIndex = 0

    private var isFirstPage: Bool { pageIndex == 0 }
    private var isLastPage: Bool { pageIndex == onboardingPages.count - 1 }

    var body: some View {
        card
            .animation(.easeInOut(duration: 0.3), value: pageIndex)
    }

    /// Фиксированный размер панели, одинаковый для всех шагов — иначе при
    /// переключении страниц с разной длиной текста высота карточки
    /// скачет, а Skip/Back/Next вместе с ней меняют положение на экране.
    /// Кнопки закреплены через .overlay(alignment:) к углам этой панели,
    /// а не встроены в стек с контентом, поэтому не двигаются вообще.
    private static let cardSize = CGSize(width: 400, height: 420)

    private var card: some View {
        ZStack {
            panelBackground

            pageContent
                .id(pageIndex)
                .padding(.horizontal, 36)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .overlay(alignment: .topTrailing) {
            skipButton
                .opacity(isLastPage ? 0 : 1)
                .disabled(isLastPage)
                .padding(20)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 14) {
                pageDots
                footer
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    private var panelBackground: some View {
        Group {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black.opacity(0.15))
                    .glassEffect(in: .rect(cornerRadius: 24))
            } else {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 24).fill(Color.black.opacity(0.15)))
            }
        }
    }

    private var pageContent: some View {
        let page = onboardingPages[pageIndex]
        return VStack(spacing: 16) {
            Image(systemName: page.symbol)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.4), radius: 6)

            Text(page.title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)

            Text(page.description)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)

            if let hint = page.hint {
                Text(hint)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }
        }
    }

    private var footer: some View {
        HStack {
            backButton
                .opacity(isFirstPage ? 0 : 1)
                .disabled(isFirstPage)

            Spacer()

            Button {
                if isLastPage {
                    finish()
                } else {
                    pageIndex += 1
                }
            } label: {
                Text(isLastPage ? "Get Started" : "Next")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var backButton: some View {
        Button("Back") { pageIndex = max(0, pageIndex - 1) }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.5))
    }

    private var skipButton: some View {
        Button("Skip") { finish() }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.5))
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(onboardingPages.indices, id: \.self) { index in
                Circle()
                    .fill(index == pageIndex ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func finish() {
        OnboardingState.hasCompletedTour = true
        onFinish()
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .frame(width: 900, height: 600)
        .background(Color.black)
}
