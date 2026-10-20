import SwiftUI

/// Онбординг первого запуска — четыре коротких экрана с анимациями (см.
/// OnboardingScenes). Пропустить нельзя: только пройти — Return/Space дальше,
/// ← назад. На экране «первая карточка» панели нет — только подсказка сверху, а
/// канва под ней принимает драг (тур ждёт настоящую карточку); после неё —
/// награда и «Continue» мышью (Return в карточке — перевод строки).
struct OnboardingView: View {
    var onboardingViewModel: OnboardingViewModel

    var body: some View {
        ZStack {
            if onboardingViewModel.isWaitingOnCanvas {
                // Внизу: сверху плашка Space и обычно первые карточки.
                canvasHint
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                // Затемнение — доска под панелью не трогается, пока идёт рассказ.
                Color.black.opacity(0.45)
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .transition(.opacity)
                panel
                    .id(onboardingViewModel.step)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: onboardingViewModel.step)
        .animation(.easeInOut(duration: 0.3), value: onboardingViewModel.isWaitingOnCanvas)
        // Return/Space на панели должны листать тур, а не печатать в карточке.
        .onAppear { releaseTextFocus() }
        .onChange(of: onboardingViewModel.step) { _, _ in releaseTextFocus() }
    }

    private func releaseTextFocus() {
        guard !onboardingViewModel.isWaitingOnCanvas else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    // MARK: - Панель

    private var panel: some View {
        VStack(spacing: 18) {
            content
            controls
        }
        .padding(24)
        .frame(width: 540)
        .background(CardSurfaceBackground(cornerRadius: 22, usesGlassEffect: false, tintOpacity: 0.22))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
    }

    @ViewBuilder
    private var content: some View {
        switch onboardingViewModel.step {
        case .hook:
            HookScene().frame(height: 230)
            heading("Scattered ideas.", "No folders, no lists \u{2014} just a space to think. Drop a thought anywhere and move it where it belongs.")
        case .home:
            heading("Where should Thoughts live?", "You can change this anytime in Settings \u{2192} General.")
            HStack(spacing: 14) {
                homeOption(.window, title: "In a window", subtitle: "A regular window, like any app.") { WindowHomeScene() }
                homeOption(.desktop, title: "On your desktop", subtitle: "Cards sit right on your wallpaper.", isRecommended: true) { DesktopHomeScene() }
            }
        case .firstCard:
            EmptyView() // этот экран — подсказка над канвой (canvasHint)
        case .finish:
            FinishScene().frame(height: 150)
            heading("You're all set.", finishText)
            HStack(spacing: 8) {
                chip("\u{2325}Tab", "All Spaces")
                chip("\u{2325}1\u{2013}9", "Switch Space")
                if onboardingViewModel.home == .desktop { chip("\u{2325}D", "Show the desktop") }
            }
        }
    }

    private var finishText: String {
        onboardingViewModel.home == .desktop
            ? "Thoughts now lives on your desktop. A cheat sheet card is waiting for you \u{2014} delete it when you know it by heart."
            : "A cheat sheet card is waiting for you on the board \u{2014} delete it when you know it by heart."
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func homeOption<Scene: View>(_ home: OnboardingHome, title: String, subtitle: String,
                                          isRecommended: Bool = false,
                                          @ViewBuilder scene: () -> Scene) -> some View {
        let selected = onboardingViewModel.home == home
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { onboardingViewModel.choose(home) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                scene().frame(height: 130)
                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if isRecommended {
                        Text("Recommended")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.08 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1)
            )
            .scaleEffect(selected ? 1 : 0.98)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chip(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(keys).font(.system(size: 12, weight: .semibold, design: .rounded))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    // MARK: - Кнопки и клавиатура

    private var controls: some View {
        HStack {
            if onboardingViewModel.canGoBack {
                Button("Back") { onboardingViewModel.back() }
                    .keyboardShortcut(onboardingViewModel.step == .home ? nil : KeyboardShortcut(.leftArrow, modifiers: []))
            }
            Spacer()
            dots
            Spacer()
            Button(onboardingViewModel.step == .finish ? "Get Started" : "Continue") { onboardingViewModel.next() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        // Невидимые кнопки ради клавиш: Space — дальше, ←/→ на экране выбора — вариант.
        .background {
            ZStack {
                Button("") { onboardingViewModel.next() }
                    .keyboardShortcut(.space, modifiers: [])
                if onboardingViewModel.step == .home {
                    Button("") { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { onboardingViewModel.choose(.window) } }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Button("") { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { onboardingViewModel.choose(.desktop) } }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                }
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step == onboardingViewModel.step ? Color.accentColor : Color.primary.opacity(0.2))
                    .frame(width: step == onboardingViewModel.step ? 16 : 6, height: 6)
            }
        }
    }

    // MARK: - Подсказка над канвой

    @ViewBuilder
    private var canvasHint: some View {
        if onboardingViewModel.didCreateCard {
            // Награда: карточка есть — можно печатать, «Continue» дальше.
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.bounce, value: onboardingViewModel.didCreateCard)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nice, that's your first card!")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Type anything in it. Drag it by the top to move, drag the corner to resize.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Button("Continue") { onboardingViewModel.next() }
                    .controlSize(.large)
            }
            .padding(12)
            .background(CardSurfaceBackground(cornerRadius: 18, usesGlassEffect: false, tintOpacity: 0.22))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else {
            HStack(spacing: 12) {
                CreateCardScene().frame(width: 110, height: 66)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Create your first card")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Drag anywhere on the board.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(CardSurfaceBackground(cornerRadius: 18, usesGlassEffect: false, tintOpacity: 0.22))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            // Подсказка не мешает тянуть по канве рядом с ней.
            .allowsHitTesting(false)
        }
    }
}

#Preview {
    OnboardingView(onboardingViewModel: OnboardingViewModel(isActive: true))
        .frame(width: 900, height: 640)
        .background(Color.black)
}
