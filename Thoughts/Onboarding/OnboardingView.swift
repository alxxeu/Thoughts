import SwiftUI

/// Онбординг первого запуска — горизонтальная панель одного размера на всех
/// экранах: слева сцена, справа текст и кнопки. Пропустить нельзя: Return/Space —
/// дальше, ← — назад. На экране 3 слева не сцена, а «окно» в настоящий Space:
/// затемнение вокруг, там — живая доска, в которой проходят вводный курс.
struct OnboardingView: View {
    var onboardingViewModel: OnboardingViewModel
    /// Нужна для заданий экрана 3: существует ли карточка, есть ли текст и тег.
    var board: BoardViewModel

    static let panelSize = CGSize(width: 860, height: 430)
    static let stageSize = CGSize(width: 500, height: 382)
    private static let inset: CGFloat = 24

    private var isSandbox: Bool { onboardingViewModel.step == .firstCard }

    var body: some View {
        GeometryReader { proxy in
            let panel = CGRect(x: (proxy.size.width - Self.panelSize.width) / 2,
                               y: (proxy.size.height - Self.panelSize.height) / 2,
                               width: Self.panelSize.width, height: Self.panelSize.height)
            let stage = CGRect(origin: CGPoint(x: panel.minX + Self.inset, y: panel.minY + Self.inset), size: Self.stageSize)
            ZStack(alignment: .topLeading) {
                // Затемнение; на экране 3 — с «окном» в Space, клики туда проходят.
                DimShape(hole: isSandbox ? stage : nil)
                    .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                    .contentShape(DimShape(hole: isSandbox ? stage : nil), eoFill: true)
                    .onTapGesture {}
                panelView
                    .frame(width: panel.width, height: panel.height)
                    .offset(x: panel.minX, y: panel.minY)
            }
            .onAppear { updateSandbox(stage) }
            .onChange(of: stage) { _, rect in updateSandbox(rect) }
            .onChange(of: onboardingViewModel.step) { _, _ in
                updateSandbox(stage)
                releaseTextFocus()
            }
        }
        .onAppear {
            TipsState.shared.isPaused = true
            releaseTextFocus()
        }
        .onDisappear {
            TipsState.shared.isPaused = false
            BoardViewModel.onboardingSandbox = nil
        }
        .onChange(of: sandboxState) { _, state in
            onboardingViewModel.sync(cardExists: state.exists, hasText: state.hasText, hasTag: state.hasTag)
        }
    }

    /// Карточка экрана 3 двигается и создаётся только внутри «окна».
    private func updateSandbox(_ stage: CGRect) {
        BoardViewModel.onboardingSandbox = isSandbox ? stage.insetBy(dx: 6, dy: 6) : nil
    }

    /// Return/Space на панели должны листать тур, а не печатать в карточке.
    private func releaseTextFocus() {
        guard !isSandbox else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private struct SandboxState: Equatable {
        var exists = false, hasText = false, hasTag = false
    }

    private var sandboxState: SandboxState {
        guard let id = onboardingViewModel.sandboxCardID,
              let card = board.cards.first(where: { $0.id == id }) else { return SandboxState() }
        return SandboxState(exists: true,
                            hasText: !card.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            hasTag: card.tagColor != nil)
    }

    // MARK: - Панель

    private var panelView: some View {
        HStack(alignment: .top, spacing: Self.inset) {
            stageView
                .frame(width: Self.stageSize.width, height: Self.stageSize.height)
            VStack(alignment: .leading, spacing: 14) {
                sideContent
                Spacer(minLength: 0)
                controls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(onboardingViewModel.step)
            .transition(.opacity)
        }
        .padding(Self.inset)
        .background(
            CardSurfaceBackground(cornerRadius: 24, usesGlassEffect: false, tintOpacity: 0.22)
                // На экране 3 под «окном» панели нет — там видна доска.
                .mask(DimShape(hole: isSandbox ? CGRect(origin: CGPoint(x: Self.inset, y: Self.inset), size: Self.stageSize) : nil)
                    .fill(style: FillStyle(eoFill: true)))
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        .animation(.easeInOut(duration: 0.3), value: onboardingViewModel.step)
    }

    // MARK: - Слева

    @ViewBuilder
    private var stageView: some View {
        switch onboardingViewModel.step {
        case .hook:
            HookScene()
        case .home:
            HStack(spacing: 12) {
                homeOption(.window, title: "In a window", subtitle: "A regular window, like any app.") { WindowHomeScene() }
                homeOption(.desktop, title: "On your desktop", subtitle: "Cards sit right on your wallpaper.", isRecommended: true) { DesktopHomeScene() }
            }
        case .firstCard:
            // «Окно» в настоящий Space: только рамка, внутри — доска.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .overlay(alignment: .bottom) {
                    if onboardingViewModel.sandboxCardID == nil, !onboardingViewModel.isSandboxDone {
                        Text("Drag anywhere in this box")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.bottom, 14)
                    }
                }
                .allowsHitTesting(false)
        case .finish:
            FinishScene()
        }
    }

    private func homeOption<Scene: View>(_ home: OnboardingHome, title: String, subtitle: String,
                                          isRecommended: Bool = false,
                                          @ViewBuilder scene: () -> Scene) -> some View {
        let selected = onboardingViewModel.home == home
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { onboardingViewModel.choose(home) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                scene().frame(maxHeight: .infinity)
                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    Text(title).font(.system(size: 13, weight: .semibold))
                }
                Text(isRecommended ? "Recommended" : " ")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.08 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Справа

    @ViewBuilder
    private var sideContent: some View {
        switch onboardingViewModel.step {
        case .hook:
            heading("Scattered ideas.", "No folders, no lists \u{2014} just a space to think. Drop a thought anywhere, write in Markdown, tag it with a color.")
        case .home:
            heading("Where should Thoughts live?", "You can change this anytime in Settings \u{2192} General.")
        case .firstCard:
            heading("Your first card", "Try it right here, in the box on the left.")
            tasks
            taskDemo
                .frame(height: 140)
        case .finish:
            heading("You\u{2019}re all set.", onboardingViewModel.home == .desktop
                    ? "Thoughts now lives on your desktop. A cheat sheet card is waiting for you \u{2014} delete it when you know it by heart."
                    : "A cheat sheet card is waiting for you on the board \u{2014} delete it when you know it by heart.")
            VStack(alignment: .leading, spacing: 8) {
                chip("\u{2325}Tab", "All Spaces")
                chip("\u{2325}1\u{2013}9", "Switch Space")
                if onboardingViewModel.home == .desktop { chip("\u{2325}D", "Show the desktop") }
            }
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tasks: some View {
        VStack(alignment: .leading, spacing: 7) {
            taskRow(.create, "Create a card", "drag in the box")
            taskRow(.type, "Write something", "Markdown works")
            taskRow(.tag, "Add a color tag", "click the dot")
            taskRow(.delete, "Delete it", "hold the \u{00D7}")
        }
    }

    private func taskRow(_ task: SandboxTask, _ title: String, _ hint: String) -> some View {
        let done = onboardingViewModel.isDone(task)
        let current = onboardingViewModel.currentTask == task
        return HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : (current ? "circle.dotted" : "circle"))
                .foregroundStyle(done ? Color.green : (current ? Color.accentColor : .secondary))
                .symbolEffect(.bounce, value: done)
            Text(title).font(.system(size: 13, weight: current ? .semibold : .regular))
                .foregroundStyle(done ? .secondary : .primary)
            Text(hint).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .animation(.easeInOut(duration: 0.25), value: done)
    }

    /// Анимация к текущему заданию; когда всё сделано — награда.
    @ViewBuilder
    private var taskDemo: some View {
        switch onboardingViewModel.currentTask {
        case .create: CreateCardScene()
        case .type: TypeTextScene()
        case .tag: TagCursorScene()
        case .delete: DeleteCursorScene()
        case nil:
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.bounce, value: onboardingViewModel.isSandboxDone)
                Text("Great \u{2014} that\u{2019}s all there is to a card.")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func chip(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.1)))
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }
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
                .disabled(isSandbox && !onboardingViewModel.isSandboxDone)
        }
        // Невидимые кнопки ради клавиш: Space — дальше (не на экране 3 — там
        // печатают в карточке), ←/→ на экране выбора — вариант.
        .background {
            ZStack {
                if !isSandbox {
                    Button("") { onboardingViewModel.next() }
                        .keyboardShortcut(.space, modifiers: [])
                }
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
}

/// Прямоугольник на всю область с вырезом-«окном» (при even-odd заливке).
struct DimShape: Shape {
    var hole: CGRect?
    var cornerRadius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if let hole {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous)
        }
        return path
    }
}
