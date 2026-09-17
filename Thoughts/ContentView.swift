import SwiftUI
import Carbon.HIToolbox

struct CornerBracket: Shape {
    var corner: EdgeHint.Corner
    var radius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length = min(rect.width, rect.height)
        let r = min(radius, length / 2)

        switch corner {
        case .topLeft:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + r, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        case .topRight:
            path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + r),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        case .bottomLeft:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY - length))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + r, y: rect.maxY),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + length, y: rect.maxY))

        case .bottomRight:
            path.move(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        }

        return path
    }
}

/// Невидимая зона для перетаскивания окна за верхнюю полосу (тайтлбар скрыт
/// через .windowStyle(.hiddenTitleBar)). WindowDragGesture доступен только с
/// macOS 15 — на macOS 14 используем NSWindow.performDrag(with:) напрямую.
struct WindowDragArea: View {
    var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
            } else {
                LegacyWindowDragView()
            }
        }
    }
}

private struct LegacyWindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableNSView {
        DraggableNSView()
    }

    func updateNSView(_ nsView: DraggableNSView, context: Context) {}
}

private final class DraggableNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// Отдаёт наружу NSWindow, хостящий этот view — тот же приём, что уже
/// использует VisualEffectBlur.Coordinator для nudge-хака, но здесь нужен
/// именно снаружи ContentView: NSApp.keyWindow/NSApp.windows.first
/// ненадёжны, когда одновременно может быть открыто окно Settings.
private struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ContentView: View {
    var viewModel: BoardViewModel
    @State private var creationStart: CGPoint?
    @State private var draftFrame: CGRect?
    @State private var placementPreview: CGRect?
    @State private var edgeHints: [EdgeHint] = []
    @State private var newlyCreatedCardID: UUID? = nil
    @State private var isWindowResizing = false
    @State private var resizeDebounceTask: Task<Void, Never>?
    @State private var isPlacementPreviewVisible = false
    @State private var isEditingWorkspaceName = false
    @State private var workspaceNameDraft = ""
    @FocusState private var isWorkspaceNameFieldFocused: Bool

    // AI для всего Space (Pro, BYOK) — Ask AI (+ Summarize внутри его
    // панели) под pill с названием. См. Thoughts/AI. Результат — новая
    // карточка на канве.
    @State private var isAskingSpaceAI = false
    @State private var spaceAIQuestion = ""
    @State private var isSpaceAIBusy = false
    @State private var spaceAIErrorMessage: String?
    /// Название функции, над иконкой которой сейчас курсор — управляет
    /// мгновенной подсветкой самой иконки.
    @State private var hoveredToolbarLabel: String?
    /// В отличие от hoveredToolbarLabel выше — не мгновенно: всплывающая
    /// подсказка под иконкой появляется только после небольшой задержки
    /// наведения (см. setToolbarHover), как обычные системные tooltips.
    @State private var tooltipVisibleLabel: String?
    @State private var tooltipTask: Task<Void, Never>?
    // Актуальный размер канвы — нужен вне GeometryReader, чтобы новая
    // AI-карточка могла стартовать анимацию из-под нотча к центру экрана.
    @State private var canvasSize: CGSize = .zero
    
    // Состояние и таймер для подсказки пустого спэйса
    @State private var showEmptyHint = false
    @State private var emptyHintTask: Task<Void, Never>?

    // Тур по фичам при первом запуске — поверх остального интерфейса, но
    // не мешает locking-логике (на первом запуске Passcode ещё не включён).
    @State private var isShowingOnboarding = !OnboardingState.hasCompletedTour

    // File → Clear Space — сам alert живёт здесь, а не в ThoughtsApp, так
    // как ему нужно реальное удаление карточек через viewModel только
    // после явного подтверждения, а не по одному нажатию пункта меню.
    @State private var isShowingClearSpaceConfirmation = false

    // Desktop Overlay — фрейм окна до включения режима, чтобы вернуть его
    // ровно как было при выключении в Settings. thoughtsWindow — конкретно
    // окно, хостящее этот canvas (не Settings/QuitGuard), см. WindowAccessor
    // ниже; NSApp.keyWindow ненадёжен здесь, так как Settings-окно вполне
    // может быть открыто и фокусно ровно в момент переключения тумблера.
    @State private var savedWindowFrame: NSRect?
    @State private var thoughtsWindow: NSWindow?
    @State private var chromeReapplyObservers: [NSObjectProtocol] = []
    @State private var isDesktopOverlayActivationPendingFullScreenExit = false

    var body: some View {
        Group {
            if viewModel.desktopOverlay.isDesktopModeActive {
                // Desktop mode: карточки полностью скрыты, окно прозрачно и
                // ignoresMouseEvents (см. onChange ниже) — реальный рабочий
                // стол должен быть виден без единого визуального следа
                // Thoughts поверх него.
                Color.clear
                    .transition(.opacity)
            } else if viewModel.isActiveSpaceLocked {
                // Полностью отдельная ветка дерева: карточки и canvas этого
                // Space physически не существуют, пока он заблокирован —
                // то же самое "выгружение", что происходит при обычном
                // переключении между Spaces (ForEach(viewModel.cards) для
                // невыбранного слота тоже не рендерится). Никакого
                // отдельного blur-слоя поверх живого контента не нужно.
                SpaceLockOverlayView(viewModel: viewModel)
                    .transition(.opacity)
            } else {
                unlockedSpaceContent
            }
        }
        .overlay {
            if isShowingOnboarding {
                OnboardingView(onFinish: { isShowingOnboarding = false })
                    .transition(.opacity)
            }
        }
        // Плавные переходы между Spaces (обычное переключение, Desktop
        // Overlay туда-обратно, лок/анлок) — раньше карточки/оверлеи
        // сразу переключались без анимации, топорно. Пружина вместо
        // плоского easeOut — привычная по ощущению кривая для macOS,
        // а не линейное затухание.
        .animation(.easeOut(duration: 0.2), value: viewModel.desktopOverlay.isDesktopModeActive)
        .animation(.easeOut(duration: 0.2), value: viewModel.isActiveSpaceLocked)
        // Смена Space сама по себе — без общего id/transition на весь
        // блок: не имитируем это одним общим кросс-фейдом. Вместо этого,
        // как у Floatspace, анимируется только УХОД старых карточек
        // (asymmetric-transition на каждой CardView ниже), новые
        // появляются сразу без входной анимации, а pill с названием
        // просто меняет текст — так выглядит собраннее, а не "будто всё
        // тает одним пятном".
        .animation(.easeOut(duration: 0.1), value: viewModel.activeSlot)
        .animation(.easeOut(duration: 0.25), value: isShowingOnboarding)
        .background(
            WindowAccessor { window in
                guard thoughtsWindow == nil else { return }
                thoughtsWindow = window
                allowWindowToBecomeKey(window)
                applyDesktopOverlayWindowState(
                    isEnabled: viewModel.desktopOverlay.isEnabled,
                    isDesktopModeActive: viewModel.desktopOverlay.isDesktopModeActive
                )
                // AppKit иногда сам переигрывает styleMask/title окна на
                // переходах фокуса (например, relock() Space Lock делает
                // makeFirstResponder(nil)) — тот же класс проблемы, что уже
                // решён для VisualEffectBlur ниже в этом файле через
                // переприменение после нотификаций, а не один раз. Здесь —
                // то же самое для chrome-настроек Desktop Overlay.
                for name: Notification.Name in [
                    NSWindow.didBecomeKeyNotification,
                    NSWindow.didResignKeyNotification,
                    NSWindow.didChangeOcclusionStateNotification
                ] {
                    chromeReapplyObservers.append(
                        NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in
                            guard viewModel.desktopOverlay.isEnabled else { return }
                            applyDesktopOverlayWindowState(
                                isEnabled: true,
                                isDesktopModeActive: viewModel.desktopOverlay.isDesktopModeActive
                            )
                        }
                    )
                }
                // Довершает включение Desktop Overlay, если оно было
                // отложено из-за того, что окно было в нативном fullscreen
                // (см. guard в applyDesktopOverlayWindowState) — level/frame
                // нельзя было применить, пока переход не завершился.
                chromeReapplyObservers.append(
                    NotificationCenter.default.addObserver(
                        forName: NSWindow.didExitFullScreenNotification,
                        object: window,
                        queue: .main
                    ) { _ in
                        guard isDesktopOverlayActivationPendingFullScreenExit else { return }
                        isDesktopOverlayActivationPendingFullScreenExit = false
                        guard viewModel.desktopOverlay.isEnabled else { return }
                        applyDesktopOverlayWindowState(
                            isEnabled: true,
                            isDesktopModeActive: viewModel.desktopOverlay.isDesktopModeActive
                        )
                    }
                )
            }
        )
        // Привязано напрямую к состоянию, которое реально коррелирует с
        // проблемой (подтверждено вручную): переход в/из заблокированного
        // Space почему-то может сбрасывать chrome-настройки окна, а переход
        // между Spaces через смену activeSlot (без вызовов AppKit вроде
        // makeFirstResponder) не всегда порождает didBecomeKey/didResignKey,
        // на которые реагирует блок выше. SwiftUI-observation здесь надёжнее
        // гадания, какая именно AppKit-нотификация выстрелит.
        .onChange(of: viewModel.isActiveSpaceLocked) { _, _ in
            guard viewModel.desktopOverlay.isEnabled else { return }
            applyDesktopOverlayWindowState(
                isEnabled: true,
                isDesktopModeActive: viewModel.desktopOverlay.isDesktopModeActive
            )
        }
        .onChange(of: viewModel.desktopOverlay.isEnabled) { _, isEnabled in
            applyDesktopOverlayWindowState(isEnabled: isEnabled, isDesktopModeActive: viewModel.desktopOverlay.isDesktopModeActive)
        }
        .onChange(of: viewModel.desktopOverlay.isDesktopModeActive) { _, isActive in
            applyDesktopOverlayWindowState(isEnabled: viewModel.desktopOverlay.isEnabled, isDesktopModeActive: isActive)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchWorkspace)) { notification in
            if let slot = notification.object as? Int {
                // Явный withAnimation здесь, а не только .animation(value:)
                // ниже — через GeometryReader → ZStack → ForEach декларативная
                // привязка по value надёжно анимирует уход старых карточек,
                // но не всегда подхватывает появление новых.
                withAnimation(.easeOut(duration: 0.1)) {
                    viewModel.switchWorkspace(to: slot)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lockCurrentSpace)) { _ in
            viewModel.lockActiveSpaceManually()
        }
        .onReceive(NotificationCenter.default.publisher(for: .replayOnboarding)) { _ in
            isShowingOnboarding = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestClearSpace)) { _ in
            isShowingClearSpaceConfirmation = true
        }
        .alert(
            "Clear \u{201C}\(viewModel.activeWorkspace?.name ?? Workspace.defaultName(forSlot: viewModel.activeSlot))\u{201D}?",
            isPresented: $isShowingClearSpaceConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All Cards", role: .destructive) {
                viewModel.clearActiveSpace()
            }
        }
        message: {
            Text("This will permanently delete all \(viewModel.cards.count) card\(viewModel.cards.count == 1 ? "" : "s") in this Space. This can\u{2019}t be undone.")
        }
    }

    private var unlockedSpaceContent: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(canvasDragGesture(in: proxy.size))
                    .onTapGesture {
                        NotificationCenter.default.post(name: .clearTextSelection, object: nil)
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }

                ForEach(viewModel.cards) { card in
                    let adaptedPosition = BoardViewModel.clampedPosition(card.position, size: card.size, canvasSize: proxy.size, topInset: effectiveTopInset)

                    CardView(
                        card: card,
                        viewModel: viewModel,
                        canvasSize: proxy.size,
                        onPlacementPreviewChange: { preview in
                            resizeDebounceTask?.cancel()
                            
                            if let preview {
                                var transaction = Transaction()
                                transaction.animation = nil
                                withTransaction(transaction) {
                                    placementPreview = preview
                                }
                                
                                resizeDebounceTask = Task {
                                    try? await Task.sleep(for: .seconds(0.05))
                                    guard !Task.isCancelled else { return }
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isPlacementPreviewVisible = true
                                    }
                                }
                            } else {
                                isPlacementPreviewVisible = false
                                placementPreview = nil
                            }
                        },
                        onEdgeHintsChange: { edgeHints = $0 }
                    )
                    .frame(width: card.size.width, height: card.size.height, alignment: .topLeading)
                    .offset(x: adaptedPosition.x, y: adaptedPosition.y)
                    // .compositingGroup() — карточка (стекло + текст +
                    // чат тега/кнопок) смешивается с тем, что позади, как
                    // один плоский слой при fade, а не покомпонентно;
                    // должно убрать серый след, который оставляло живое
                    // стекло при анимированном opacity.
                    .compositingGroup()
                    // Исчезновение — быстрее появления: своя анимация на
                    // каждой стороне через .animation(_:) на AnyTransition,
                    // а не общая длительность из withAnimation в месте
                    // мутации activeSlot.
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.85))
                                .animation(.easeOut(duration: 0.08)),
                            removal: .opacity.combined(with: .scale(scale: 0.85))
                                .animation(.easeOut(duration: 0.05))
                        )
                    )
                    .onAppear {
                        if newlyCreatedCardID == card.id {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                NotificationCenter.default.post(name: .focusNewCard, object: card.id)
                                newlyCreatedCardID = nil
                            }
                        }
                    }
                }
                
                if let placementPreview {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.05))
                        .frame(width: placementPreview.width, height: placementPreview.height, alignment: .topLeading)
                        .offset(x: placementPreview.minX, y: placementPreview.minY)
                        .allowsHitTesting(false)
                        .opacity(isPlacementPreviewVisible ? 1.0 : 0.0)
                }
                
                ForEach(Array(edgeHints.enumerated()), id: \.offset) { _, hint in
                    switch hint {
                    case .edge(_, let frame):
                        Capsule()
                            .fill(Color.primary.opacity(0.3))
                            .blur(radius: 1)
                            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                            .offset(x: frame.minX, y: frame.minY)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                        
                    case .corner(let corner, let frame):
                        CornerBracket(corner: corner)
                            .stroke(
                                Color.primary.opacity(0.3),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                            )
                            .blur(radius: 1)
                            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                            .offset(x: frame.minX, y: frame.minY)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                
                if let draftFrame {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: draftFrame.width, height: draftFrame.height, alignment: .topLeading)
                        .offset(x: draftFrame.minX, y: draftFrame.minY)
                        .allowsHitTesting(false)
                }
                
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: 76)
                    WindowDragArea()
                }
                .frame(height: effectiveTopInset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            
            .coordinateSpace(name: "canvas")
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeOut(duration: 0.12), value: edgeHints.count)
            
            .onChange(of: proxy.size) { _, newValue in
                isWindowResizing = true
                canvasSize = newValue

                resizeDebounceTask?.cancel()
                resizeDebounceTask = Task {
                    try? await Task.sleep(for: .seconds(0.15))
                    guard !Task.isCancelled else { return }
                    isWindowResizing = false
                }
            }
            .onAppear {
                canvasSize = proxy.size
            }
        }
        .background(Color.clear)
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Group {
                        if isEditingWorkspaceName {
                            TextField("Space name", text: $workspaceNameDraft)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .frame(width: 100)
                                .focused($isWorkspaceNameFieldFocused)
                                .onSubmit { commitWorkspaceRename() }
                                .onExitCommand { cancelWorkspaceRename() }
                                .onChange(of: isWorkspaceNameFieldFocused) { _, focused in
                                    if !focused { commitWorkspaceRename() }
                                }
                                .onChange(of: workspaceNameDraft) { _, newValue in
                                    if newValue.count > BoardViewModel.maxWorkspaceNameLength {
                                        workspaceNameDraft = String(newValue.prefix(BoardViewModel.maxWorkspaceNameLength))
                                    }
                                }
                        } else {
                            Text(viewModel.activeWorkspace?.name ?? Workspace.defaultName(forSlot: viewModel.activeSlot))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.9))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isEditingWorkspaceName {
                            startWorkspaceRename()
                        }
                    }

                    // Иконки-действия пристёгнуты к тому же pill'у, что и
                    // название — не отдельные капсулы под ним, чтобы новая
                    // функция была ещё одной иконкой в этом же ряду, а не
                    // ещё одной строкой вниз.
                    if !isEditingWorkspaceName {
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 1, height: 14)

                        Button {
                            dismissToolbarTooltip()
                            withAnimation(spaceAISpring) { isAskingSpaceAI.toggle() }
                        } label: {
                            Image(systemName: "sparkle")
                                // Развёрнутая на 45° звёздочка читается как
                                // крестик — понятная подсказка "нажми ещё
                                // раз, чтобы закрыть".
                                .rotationEffect(.degrees(isAskingSpaceAI ? 45 : 0))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.white.opacity(isAskingSpaceAI || hoveredToolbarLabel == "Ask AI" ? 1 : 0.85))
                        .font(.system(size: 15))
                        .onHover { setToolbarHover($0, "Ask AI") }
                        .overlay(alignment: .top) { toolbarTooltip("Ask AI") }

                        Button {
                            dismissToolbarTooltip()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                viewModel.tidyCards(canvasSize: canvasSize, topInset: effectiveTopInset)
                            }
                        } label: {
                            Image(systemName: "square.grid.2x2.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.white.opacity(hoveredToolbarLabel == "Tidy Cards" ? 1 : 0.85))
                        .font(.system(size: 15))
                        .disabled(viewModel.cards.isEmpty)
                        .onHover { setToolbarHover($0, "Tidy Cards") }
                        .overlay(alignment: .top) { toolbarTooltip("Tidy Cards") }

                        Button {
                            dismissToolbarTooltip()
                            NotificationCenter.default.post(name: .requestClearSpace, object: nil)
                        } label: {
                            Image(systemName: "trash.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.white.opacity(hoveredToolbarLabel == "Clear Space" ? 1 : 0.85))
                        .font(.system(size: 15))
                        .disabled(viewModel.cards.isEmpty)
                        .onHover { setToolbarHover($0, "Clear Space") }
                        .overlay(alignment: .top) { toolbarTooltip("Clear Space") }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.1)))

                if isAskingSpaceAI {
                    askAIPanel
                }

                // Текст подсказки
                if showEmptyHint && viewModel.cards.isEmpty {
                    Text("Drag anywhere to create your first card")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.primary.opacity(0.3))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.top, workspacePillTopPadding)
            .onReceive(NotificationCenter.default.publisher(for: .clearTextSelection)) { _ in
                // Клик по свободному холсту закрывает панель Ask AI, но
                // только если в поле ещё ничего не напечатано — не хотим
                // терять черновик вопроса случайным кликом мимо.
                guard isAskingSpaceAI, spaceAIQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                withAnimation(spaceAISpring) { isAskingSpaceAI = false }
            }
        }
        .onAppear {
            updateEmptyHintState()
        }
        .onChange(of: viewModel.activeSlot) { _, _ in
            updateEmptyHintState()
        }
        .onChange(of: viewModel.cards.isEmpty) { _, _ in
            updateEmptyHintState()
        }
        .alert("AI Error", isPresented: Binding(
            get: { spaceAIErrorMessage != nil },
            set: { if !$0 { spaceAIErrorMessage = nil } }
        )) {
            Button("OK") { spaceAIErrorMessage = nil }
        } message: {
            Text(spaceAIErrorMessage ?? "")
        }
    }

    private var spaceAISpring: Animation { .spring(response: 0.4, dampingFraction: 0.76) }

    /// Раскрывается/закрывается через insertion/removal (не морфинг pill'а
    /// — sparkle теперь просто иконка в кластере рядом с названием, см.
    /// .overlay(alignment: .top) в body), с масштабом от верхнего края и
    /// пружиной на входе. Summarize/Extract — иконки в левом нижнем углу
    /// того же поля, а не отдельная строка кнопок под ним; подсказки —
    /// тот же toolbarTooltip/setToolbarHover, что у верхнего кластера.
    private var askAIPanel: some View {
        AIPromptTextView(text: $spaceAIQuestion, shouldFocus: isAskingSpaceAI) {
            askSpaceAI()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 130)
        .onExitCommand {
            withAnimation(spaceAISpring) { isAskingSpaceAI = false }
            spaceAIQuestion = ""
        }
        // NSTextView не даёт placeholder "из коробки" (в отличие от
        // NSTextField/SwiftUI TextField) — просто текст поверх, скрытый,
        // как только начали печатать. Отступы подобраны под
        // textContainerInset (6) + дефолтный lineFragmentPadding NSTextView (5).
        .overlay(alignment: .topLeading) {
            if spaceAIQuestion.isEmpty {
                Text("Ask about your project…")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .padding(.leading, 11)
                    .padding(.top, 6)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 12) {
                Button {
                    dismissToolbarTooltip()
                    summarizeSpace()
                } label: {
                    Image(systemName: "sparkles")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(hoveredToolbarLabel == "Summarize" ? 1 : 0.85))
                .font(.system(size: 14))
                .disabled(isSpaceAIBusy || spaceAIContextText().isEmpty)
                .onHover { setToolbarHover($0, "Summarize") }
                .overlay(alignment: .top) { toolbarTooltip("Summarize") }

                Button {
                    dismissToolbarTooltip()
                    extractActionItems()
                } label: {
                    Image(systemName: "sparkle.text.clipboard")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(hoveredToolbarLabel == "Extract" ? 1 : 0.85))
                .font(.system(size: 14))
                .disabled(isSpaceAIBusy || spaceAIContextText().isEmpty)
                .onHover { setToolbarHover($0, "Extract") }
                .overlay(alignment: .top) { toolbarTooltip("Extract") }

                if isSpaceAIBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
            .padding(6)
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                askSpaceAI()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white.opacity(0.85))
            .disabled(isSpaceAIBusy || spaceAIQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(5)
        }
        .padding(6)
        .frame(width: 300)
        .background(CardSurfaceBackground(cornerRadius: 16, usesGlassEffect: false, tintOpacity: 0.15, materialStyle: .thickMaterial))
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.5, anchor: .top).combined(with: .opacity)
                    .animation(spaceAISpring),
                removal: .scale(scale: 0.5, anchor: .top).combined(with: .opacity)
                    .animation(.easeIn(duration: 0.15))
            )
        )
    }

    private func spaceAIContextText() -> String {
        viewModel.cards
            .filter { $0.privacyMode == .none && !$0.text.isEmpty }
            .map(\.text)
            .joined(separator: "\n---\n")
    }

    private func summarizeSpace() {
        let context = spaceAIContextText()
        guard !context.isEmpty, !isSpaceAIBusy else { return }
        isSpaceAIBusy = true
        Task {
            do {
                let service = try AITextServiceFactory.makeActiveService()
                let result = try await service.generate(
                    systemPrompt: AISpaceAction.summarizeSystemPrompt,
                    userText: context
                )
                await MainActor.run {
                    insertAIResultCard(result)
                    withAnimation(spaceAISpring) { isAskingSpaceAI = false }
                    isSpaceAIBusy = false
                }
            } catch {
                await MainActor.run {
                    spaceAIErrorMessage = error.localizedDescription
                    isSpaceAIBusy = false
                }
            }
        }
    }

    private func extractActionItems() {
        let context = spaceAIContextText()
        guard !context.isEmpty, !isSpaceAIBusy else { return }
        isSpaceAIBusy = true
        Task {
            do {
                let service = try AITextServiceFactory.makeActiveService()
                let result = try await service.generate(
                    systemPrompt: AISpaceAction.extractActionItemsSystemPrompt,
                    userText: context
                )
                await MainActor.run {
                    insertAIResultCard(result)
                    withAnimation(spaceAISpring) { isAskingSpaceAI = false }
                    isSpaceAIBusy = false
                }
            } catch {
                await MainActor.run {
                    spaceAIErrorMessage = error.localizedDescription
                    isSpaceAIBusy = false
                }
            }
        }
    }

    private func askSpaceAI() {
        let question = spaceAIQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSpaceAIBusy else { return }
        let context = spaceAIContextText()
        isSpaceAIBusy = true
        Task {
            do {
                let service = try AITextServiceFactory.makeActiveService()
                let userText = context.isEmpty ? question : "Notes:\n\(context)\n\nQuestion: \(question)"
                let result = try await service.generate(
                    systemPrompt: AISpaceAction.askSystemPrompt,
                    userText: userText
                )
                await MainActor.run {
                    insertAIResultCard(result)
                    spaceAIQuestion = ""
                    withAnimation(spaceAISpring) { isAskingSpaceAI = false }
                    isSpaceAIBusy = false
                }
            } catch {
                await MainActor.run {
                    spaceAIErrorMessage = error.localizedDescription
                    isSpaceAIBusy = false
                }
            }
        }
    }

    /// Не выставляет newlyCreatedCardID — та карточка сразу получает фокус
    /// текстового ввода (.focusNewCard), что фактически "активирует" её и
    /// сразу же снимало бы постоянную AI-подсветку (см. aiHighlightedCardIDs
    /// и CardView) прежде, чем пользователь вообще успеет её заметить.
    private func insertAIResultCard(_ text: String) {
        let size = CGSize(width: 280, height: 220)
        let origin = CGPoint(
            x: max(0, (canvasSize.width - size.width) / 2),
            y: max(0, (canvasSize.height - size.height) / 2)
        )
        let card = viewModel.addCard(at: origin, size: size)
        card.text = text
        card.isAIGenerated = true
        viewModel.saveImmediately()
        viewModel.aiHighlightedCardIDs.insert(card.id)
    }

    private func updateEmptyHintState() {
        emptyHintTask?.cancel()
        showEmptyHint = false
        
        guard viewModel.cards.isEmpty else { return }
        
        emptyHintTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                showEmptyHint = true
            }
        }
    }

    /// Применяет/откатывает уровень, collectionBehavior, ignoresMouseEvents
    /// и фрейм окна для Desktop Overlay — см. план в
    /// buzzing-squishing-wombat.md. Значение уровня подобрано эмпирически
    /// (публичной константы "чуть выше иконок, чуть ниже виджетов" у Apple
    /// нет) и может понадобиться донастроить.
    /// В обычном окне — прежняя маленькая граница. В Desktop Overlay окно
    /// растянуто на весь экран, и карточки не должны упираться в самый
    /// верх/вырез камеры — там, где обычно сидят системные виджеты.
    private var effectiveTopInset: CGFloat {
        viewModel.desktopOverlay.isEnabled ? BoardViewModel.desktopOverlayTopInset : BoardViewModel.topCreationLimit
    }

    /// Плашка с именем Space — обычный SwiftUI-оверлей этой же канвы (не
    /// chrome окна), так что отступ под неё можно менять независимо от
    /// самого окна/frame — без компромисса с покрытием экрана, в отличие
    /// от системных элементов. В обычном окне — как раньше, 10pt.
    private var workspacePillTopPadding: CGFloat {
        guard viewModel.desktopOverlay.isEnabled else { return 10 }
        return (NSScreen.main?.safeAreaInsets.top ?? 0) + 12
    }

    private func applyDesktopOverlayWindowState(isEnabled: Bool, isDesktopModeActive: Bool) {
        guard let window = thoughtsWindow else { return }

        // Нативный fullscreen — отдельная macOS Space, level/frame внутри
        // неё игнорируются композитором (а styleMask-правки — нет, отсюда
        // рассинхрон: кнопки/pill уже перестроились, а окно так и не легло
        // на уровень иконок стола). Сначала выходим из fullscreen и ждём
        // завершения перехода (didExitFullScreenNotification, см. ниже),
        // и только потом применяем остальную конфигурацию.
        if isEnabled, window.styleMask.contains(.fullScreen) {
            isDesktopOverlayActivationPendingFullScreenExit = true
            window.toggleFullScreen(nil)
            return
        }

        if isEnabled {
            if savedWindowFrame == nil {
                savedWindowFrame = window.frame
            }
            // Уровень асимметричный между режимами — подтверждено реальным
            // кодом Floatspace (native_desktop.rs): Desktop mode ниже
            // иконок стола (окно совсем не мешает, даже не "прозрачно
            // мешает"), Workspace mode выше иконок, но по-прежнему ниже
            // обычных окон приложений. Раньше здесь был один и тот же
            // фиксированный уровень в обоих режимах — работало, но не
            // совпадало с проверенным эталоном без явной причины.
            let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
            window.level = NSWindow.Level(
                rawValue: isDesktopModeActive ? desktopIconLevel - 1 : desktopIconLevel + 1
            )
            window.collectionBehavior = [.ignoresCycle]
            // В обычном режиме "прозрачность" фона держится целиком на
            // VisualEffectBlur (живой блюр того, что позади окна) — само
            // NSWindow остаётся непрозрачным по умолчанию. В Desktop mode
            // блюр скрыт вместе с карточками (см. body/ThoughtsApp.swift), и
            // без явного isOpaque/backgroundColor = .clear вместо настоящего
            // стола был виден сплошной непрозрачный фон окна.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            // Floatspace на Tauri создаёт окно изначально безрамочным, ему
            // это не нужно. WindowGroup в SwiftUI всегда рождает titled-окно
            // (hiddenTitleBar прячет только полосу, не сами traits) — без
            // явного снятия traits из styleMask курсор у верхнего края
            // показывает настоящие traffic-light кнопки на весь экран.
            // .titled — не только сами кнопки, но и причина зазора под
            // menu bar: у titled-окон AppKit сам поджимает frame ниже
            // строки меню, даже если явно попросить Y=0 через setFrame.
            // Полностью безрамочное окно (как у Floatspace, создаваемого
            // borderless с самого начала) это ограничение не имеет.
            window.styleMask.remove([.closable, .miniaturizable, .resizable, .titled])
            window.titleVisibility = .hidden
            window.title = ""
            // Плавающий title pill позиционируется относительно верхнего
            // края фрейма окна (подтверждено эмпирически), поэтому подвинуть
            // его ниже без потери полного покрытия экрана сверху невозможно
            // — эти две вещи завязаны на один и тот же frame. Полное
            // покрытие приоритетнее (явно попросили не обрезать снова),
            // так что фрейм всегда во весь экран, начиная с Y=0.
            if let screen = window.screen ?? NSScreen.main {
                window.setFrame(screen.frame, display: true, animate: false)
            }
            registerDesktopOverlayHotKeys()
        } else {
            isDesktopOverlayActivationPendingFullScreenExit = false
            GlobalHotKeyManager.shared.unregisterAll()
            window.level = .normal
            window.collectionBehavior = []
            window.hasShadow = true
            window.styleMask.insert([.closable, .miniaturizable, .resizable, .titled])
            window.titleVisibility = .visible
            window.title = "Thoughts"
            if let savedWindowFrame {
                window.setFrame(savedWindowFrame, display: true, animate: false)
            }
            savedWindowFrame = nil
        }

        window.ignoresMouseEvents = isEnabled && isDesktopModeActive
    }

    /// ⌥D и ⌥1–9 как глобальные хоткеты (см. GlobalHotKeyManager) — должны
    /// срабатывать, даже когда активное приложение не Thoughts, а Finder
    /// (ровно так и есть в Desktop mode после клика по иконке на столе).
    /// Виртуальные keyCode — физические позиции клавиш на ANSI-клавиатуре,
    /// не зависят от активной раскладки (в отличие от charactersIgnoring-
    /// Modifiers, который для той же клавиши на русской раскладке вернул бы
    /// не "1"–"9"/"d").
    private func registerDesktopOverlayHotKeys() {
        GlobalHotKeyManager.shared.unregisterAll()
        let optionMask = UInt32(optionKey)

        GlobalHotKeyManager.shared.register(keyCode: 2 /* kVK_ANSI_D */, modifiers: optionMask) {
            // Иначе зажатое ⌥D (авто-повтор клавиши) непрерывно шлёт один
            // и тот же вход в Desktop mode заново.
            guard !viewModel.desktopOverlay.isDesktopModeActive else { return }
            viewModel.desktopOverlay.isDesktopModeActive = true
        }

        let digitKeyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // kVK_ANSI_1...9
        for (index, keyCode) in digitKeyCodes.enumerated() {
            let slot = index + 1
            GlobalHotKeyManager.shared.register(keyCode: keyCode, modifiers: optionMask) {
                viewModel.desktopOverlay.isDesktopModeActive = false
                NotificationCenter.default.post(name: .switchWorkspace, object: slot)
            }
        }
    }

    private func canvasDragGesture(in canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("canvas"))
            .onChanged { value in
                NotificationCenter.default.post(name: .clearTextSelection, object: nil)
                NSApp.keyWindow?.makeFirstResponder(nil)
                if creationStart == nil {
                    creationStart = BoardViewModel.clampedPosition(value.startLocation, size: .zero, canvasSize: canvasSize, topInset: effectiveTopInset)
                }
                guard let start = creationStart else { return }
                let current = BoardViewModel.clampedPosition(value.location, size: .zero, canvasSize: canvasSize, topInset: effectiveTopInset)

                let origin = CGPoint(x: min(start.x, current.x), y: min(start.y, current.y))
                let size = CGSize(
                    width: max(BoardViewModel.minCardSize, abs(current.x - start.x)),
                    height: max(BoardViewModel.minCardSize, abs(current.y - start.y))
                )
                // origin выше зажат по точкам start/current (size: .zero), но
                // после раздутия до minCardSize дальний край может вылезти за
                // канву — та же проблема, что clampedPosition уже решает для
                // отображения обычных карточек, но с учётом их реального size.
                let clampedOrigin = BoardViewModel.clampedPosition(origin, size: size, canvasSize: canvasSize, topInset: effectiveTopInset)
                draftFrame = CGRect(origin: clampedOrigin, size: size)
            }
            .onEnded { _ in
                defer { creationStart = nil; draftFrame = nil }
                guard let frame = draftFrame else { return }
                
                viewModel.addCard(at: frame.origin, size: frame.size)
                
                if let newCard = viewModel.cards.last {
                    newlyCreatedCardID = newCard.id
                }
            }
    }

    /// Не просто `hoveredToolbarLabel = inside ? label : nil` — если курсор
    /// уходит с одной иконки сразу на соседнюю, exit-событие первой может
    /// прийти ПОСЛЕ enter-события второй, и голое присваивание стёрло бы
    /// уже выставленный новый label. Очищаем только если он всё ещё
    /// принадлежит этой же иконке.
    private func setToolbarHover(_ inside: Bool, _ label: String) {
        if inside {
            hoveredToolbarLabel = label
        } else if hoveredToolbarLabel == label {
            hoveredToolbarLabel = nil
        }

        tooltipTask?.cancel()
        if inside {
            tooltipTask = Task {
                try? await Task.sleep(for: .seconds(0.45))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.1)) {
                    tooltipVisibleLabel = label
                }
            }
        } else if tooltipVisibleLabel == label {
            withAnimation(.easeOut(duration: 0.08)) {
                tooltipVisibleLabel = nil
            }
        }
    }

    /// Отдельно от setToolbarHover — щёлкая по кнопке, курсор физически
    /// остаётся на месте (onHover не получает "мышь ушла"), так что без
    /// явной отмены подсказка осталась бы висеть поверх уже открытой панели.
    private func dismissToolbarTooltip() {
        tooltipTask?.cancel()
        tooltipVisibleLabel = nil
    }

    @ViewBuilder
    private func toolbarTooltip(_ label: String) -> some View {
        if tooltipVisibleLabel == label {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                // Обычный Color.black.opacity(...) на и без того тёмном
                // фоне канвы визуально неотличим от полностью непрозрачного
                // — настоящий материал реально размывает/пропускает то,
                // что под ним, а не просто гасит альфой поверх тёмного.
                .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
                .fixedSize()
                .allowsHitTesting(false)
                .offset(y: 24)
                .transition(.opacity)
        }
    }

    private func startWorkspaceRename() {
        workspaceNameDraft = viewModel.activeWorkspace?.name ?? Workspace.defaultName(forSlot: viewModel.activeSlot)
        isEditingWorkspaceName = true
        DispatchQueue.main.async {
            isWorkspaceNameFieldFocused = true
        }
    }

    private func commitWorkspaceRename() {
        guard isEditingWorkspaceName else { return }
        viewModel.renameActiveWorkspace(to: workspaceNameDraft)
        isEditingWorkspaceName = false
    }

    private func cancelWorkspaceRename() {
        isEditingWorkspaceName = false
    }
}

#Preview {
    ContentView(viewModel: BoardViewModel())
        .frame(width: 900, height: 600)
}
