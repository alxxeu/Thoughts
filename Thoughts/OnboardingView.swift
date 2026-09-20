import SwiftUI

/// Показывается один раз при первом запуске. Первые 5 шагов — интерактивные:
/// продвигает не кнопка, а настоящее действие пользователя на живой канве
/// (см. OnboardingGateEvent/хуки в CardView, TagPopoverView, ContentView —
/// и canvasDragGesture, и .onReceive(.switchWorkspace) для ⌥1-9). Оставшиеся
/// 3 требуют либо уже включённого Passcode/Desktop Overlay в Settings, либо
/// происходят вне приложения (Spotlight) — их честно "заставить сделать" на
/// чистой установке нельзя, поэтому они остаются информационными (Next).
/// Флаг завершения — в UserDefaults, тот же стиль ключей, что в
/// SecuritySettings ("namespace.name").
enum OnboardingState {
    private static let hasCompletedKey = "onboarding.hasCompletedTour"

    static var hasCompletedTour: Bool {
        get { UserDefaults.standard.bool(forKey: hasCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedKey) }
    }
}

/// Реальные действия пользователя, на которые может быть "завязан"
/// интерактивный шаг — см. OnboardingViewModel.handle.
enum OnboardingGateEvent {
    case cardCreated, cardMoved, cardResized, tagColorSet, spoilerSet, spaceSwitched
}

enum OnboardingStepKind {
    /// Продвигается только когда случится одно из перечисленных событий —
    /// не по клику на кнопку (кнопки в такой панели вообще нет, см.
    /// OnboardingCoachmarkView).
    case gated([OnboardingGateEvent])
    /// Обычный шаг-подсказка — продвигается по кнопке Next/Get Started.
    case informational
}

enum OnboardingStepIcon {
    case animatedCreate, animatedMoveResize, animatedTagColor, animatedSpoiler
    case symbol(String)
}

private struct OnboardingStep {
    let title: String
    let description: String
    let hint: String?
    let kind: OnboardingStepKind
    let icon: OnboardingStepIcon

    init(title: String, description: String, hint: String? = nil, kind: OnboardingStepKind, icon: OnboardingStepIcon) {
        self.title = title
        self.description = description
        self.hint = hint
        self.kind = kind
        self.icon = icon
    }
}

/// Порядок и формулировки — по реальным жестам/шорткатам приложения, не
/// маркетинговый текст. Если фича поменяется, шаги стоит поправить вместе
/// с ней, а не оставлять как заглушку.
private let onboardingSteps: [OnboardingStep] = [
    OnboardingStep(
        title: "Welcome to Thoughts",
        description: "Drag anywhere to create your first card.",
        kind: .gated([.cardCreated]),
        icon: .animatedCreate
    ),
    OnboardingStep(
        title: "Move & Resize",
        description: "Drag a card to move it. Drag its corner to resize.",
        kind: .gated([.cardMoved, .cardResized]),
        icon: .animatedMoveResize
    ),
    OnboardingStep(
        title: "Color Tags",
        description: "Click the dot in a card's corner and pick a color to tag it.",
        kind: .gated([.tagColorSet]),
        icon: .animatedTagColor
    ),
    OnboardingStep(
        title: "Card Privacy",
        description: "From that same dot, blur a card's contents with Spoiler.",
        kind: .gated([.spoilerSet]),
        icon: .animatedSpoiler
    ),
    OnboardingStep(
        title: "Multiple Spaces",
        description: "Press \u{2325}1 through \u{2325}9 to switch to another Space. Click the name at the top anytime to rename the current one.",
        hint: "\u{2325}1 \u{2013} \u{2325}9",
        kind: .gated([.spaceSwitched]),
        icon: .symbol("square.grid.3x3")
    ),
    OnboardingStep(
        title: "Lock an Entire Space",
        description: "Turn on Passcode in Settings \u{2192} Security to protect any Space, then lock the current one instantly.",
        hint: "\u{2318}L",
        kind: .informational,
        icon: .symbol("lock.shield")
    ),
    OnboardingStep(
        title: "Desktop Overlay",
        description: "Turn on Desktop Overlay in Settings to have Thoughts live right on your Desktop, above the icons. Press \u{2325}D to reveal the Desktop; switch to any Space to come back.",
        hint: "\u{2325}D",
        kind: .informational,
        icon: .symbol("macwindow.on.rectangle")
    ),
    OnboardingStep(
        title: "Find Anything Instantly",
        description: "Your cards are indexed in system Spotlight — search their text from anywhere on your Mac.",
        hint: "\u{2318}Space",
        kind: .informational,
        icon: .symbol("magnifyingglass")
    )
]

/// Состояние интерактивного тура. Не хранит BoardViewModel — все гейты
/// приходят событиями (прямой вызов handle(.cardCreated) из ContentView,
/// остальные три — через NotificationCenter из CardView/TagPopoverView), а
/// не реактивным опросом состояния карточек. Это принципиально: опрос вида
/// "есть ли уже тегированная карточка" мгновенно "проматывал" бы шаги 3-4
/// при Replay Onboarding на непустом Space, где такие карточки уже есть.
/// А move обязан гейтиться на onEnded (коммит), а не на onChanged — иначе
/// шаг 2 засчитывался бы на первый же пиксель драга, а не на реальное
/// перемещение.
@Observable
final class OnboardingViewModel {
    private(set) var currentStepIndex = 0
    var isActive: Bool

    init() {
        isActive = !OnboardingState.hasCompletedTour
    }

    fileprivate var currentStep: OnboardingStep { onboardingSteps[currentStepIndex] }
    var isLastStep: Bool { currentStepIndex == onboardingSteps.count - 1 }

    /// "Replay Onboarding" в Settings → General — всегда с нуля, а не с
    /// того шага, на котором тур когда-то остановился.
    func start() {
        currentStepIndex = 0
        isActive = true
    }

    /// Единая точка входа для всех 4 гейтов интерактивных шагов — не
    /// действует, если тур неактивен или текущий шаг не ждёт именно это
    /// событие (так что случайное несвязанное действие в процессе тура
    /// просто ничего не делает, не ломает и не пропускает шаги).
    func handle(_ event: OnboardingGateEvent) {
        guard isActive else { return }
        guard case .gated(let events) = currentStep.kind, events.contains(event) else { return }
        advance()
    }

    func advanceInformational() {
        guard isActive, case .informational = currentStep.kind else { return }
        advance()
    }

    func skip() {
        finish()
    }

    private func advance() {
        if isLastStep {
            finish()
        } else {
            currentStepIndex += 1
        }
    }

    private func finish() {
        OnboardingState.hasCompletedTour = true
        isActive = false
    }
}

struct OnboardingView: View {
    var onboardingViewModel: OnboardingViewModel

    @State private var isShowingSkipConfirmation = false

    var body: some View {
        stepContent
            .id(onboardingViewModel.currentStepIndex)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                removal: .opacity.combined(with: .scale(scale: 0.96))
            ))
            .animation(.easeInOut(duration: 0.3), value: onboardingViewModel.currentStepIndex)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .alert("Skip the Tour?", isPresented: $isShowingSkipConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Skip", role: .destructive) {
                    onboardingViewModel.skip()
                }
            } message: {
                Text("You can come back to it anytime from Settings \u{2192} General \u{2192} Replay Onboarding.")
            }
    }

    private var stepContent: some View {
        let step = onboardingViewModel.currentStep
        let informational = isInformational(step)
        return OnboardingCoachmarkView(
            icon: { iconView(for: step.icon) },
            title: step.title,
            description: step.description,
            hint: step.hint,
            showsSkip: !onboardingViewModel.isLastStep,
            onSkip: { isShowingSkipConfirmation = true },
            primaryButtonTitle: informational ? (onboardingViewModel.isLastStep ? "Get Started" : "Next") : nil,
            onPrimary: informational ? { onboardingViewModel.advanceInformational() } : nil
        )
    }

    private func isInformational(_ step: OnboardingStep) -> Bool {
        if case .informational = step.kind { return true }
        return false
    }

    @ViewBuilder
    private func iconView(for icon: OnboardingStepIcon) -> some View {
        switch icon {
        case .animatedCreate: CreateCardGestureIcon()
        case .animatedMoveResize: MoveResizeGestureIcon()
        case .animatedTagColor: TagColorGestureIcon()
        case .animatedSpoiler: SpoilerGestureIcon()
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.primary.opacity(0.9))
                .shadow(color: .black.opacity(0.4), radius: 6)
        }
    }
}

#Preview {
    OnboardingView(onboardingViewModel: OnboardingViewModel())
        .frame(width: 900, height: 600)
        .background(Color.black)
}
