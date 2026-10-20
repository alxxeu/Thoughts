import SwiftUI

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
    /// Отдаётся в SettingsNavigation — см. комментарий там.
    @Environment(\.openWindow) private var openWindow
    @State private var creationStart: CGPoint?
    @State private var draftFrame: CGRect?
    @State private var placementPreview: CGRect?
    @State private var edgeHints: [EdgeHint] = []
    @State private var newlyCreatedCardID: UUID? = nil
    @State private var placementPreviewTask: Task<Void, Never>?
    @State private var isPlacementPreviewVisible = false

    // Focus Mode (Cmd+F) — чистое состояние отображения, ничего не
    // персистится: position/size самой карточки не трогаются, фокус лишь
    // переопределяет их на время. textFocusedCardID — какая карточка
    // сейчас держит текстовый курсор, именно она и фокусируется.
    @State private var focusedCardID: UUID?
    @State private var textFocusedCardID: UUID?
    // Подсказка про выход всплывает не сразу — тот же принцип, что у
    // подсказки пустого Space ниже: сначала дать поработать, напомнить
    // только если человек задержался. Статичная (без holdFor) — держится,
    // пока фокус не будет снят снаружи.
    @State private var focusExitHint = HintTimer()
    /// Карточка, которая прямо сейчас едет в фокус или обратно. Пока она
    /// в переходе, её текст и контролы прячутся — см. setFocusedCard.
    @State private var focusTransitionCardID: UUID?
    @State private var focusTransitionTask: Task<Void, Never>?

    // Актуальный размер канвы — нужен вне GeometryReader: плашке Space
    // (Tidy Cards и место для новой AI-карточки).
    @State private var canvasSize: CGSize = .zero
    
    // Подсказка пустого спэйса — статичная (без holdFor), держится, пока
    // не появится первая карточка.
    @State private var emptyHint = HintTimer()

    // Интерактивный тур по фичам при первом запуске — поверх остального
    // интерфейса, но не мешает locking-логике (на первом запуске Passcode
    // ещё не включён). Состояние/гейты — см. OnboardingViewModel.
    @State private var onboardingViewModel = OnboardingViewModel()

    // File → Clear Space — сам alert живёт здесь, а не в ThoughtsApp, так
    // как ему нужно реальное удаление карточек через viewModel только
    // после явного подтверждения, а не по одному нажатию пункта меню.
    @State private var isShowingClearSpaceConfirmation = false

    @State private var overlayWindow = DesktopOverlayWindowController()

    var body: some View {
        Group {
            if viewModel.desktopOverlay.isDesktopModeActive {
                // Desktop mode: карточки полностью скрыты, окно прозрачно и
                // ignoresMouseEvents (см. onChange ниже) — реальный рабочий
                // стол должен быть виден без единого визуального следа
                // Thoughts поверх него.
                Color.clear
                    .transition(.opacity)
            } else {
                // Отдельная вложенная Group — лок/анлок анимируется
                // изолированно от Desktop Mode выше, см. .transition(.identity)
                // на unlockedSpaceContent ниже.
                Group {
                    if viewModel.isActiveSpaceLocked {
                        // Полностью отдельная ветка дерева: карточки и canvas
                        // этого Space physически не существуют, пока он
                        // заблокирован — то же самое "выгружение", что
                        // происходит при обычном переключении между Spaces
                        // (ForEach(viewModel.cards) для невыбранного слота
                        // тоже не рендерится). Никакого отдельного blur-слоя
                        // поверх живого контента не нужно.
                        SpaceLockOverlayView(viewModel: viewModel)
                            .transition(.opacity)
                    } else {
                        // .identity, а не дефолтный .opacity — иначе при
                        // блокировке карточки и полупрозрачный звёздный
                        // оверлей 0.2с кросс-фейдятся ОДНОВРЕМЕННО, и текст
                        // карточек явно просвечивает сквозь ещё-не-непрозрачный
                        // StarField до того, как он долистает fade-in. Карточки
                        // при блокировке должны исчезать мгновенно (оверлей и
                        // так их визуально накрывает с первого кадра), а при
                        // разблокировке — мгновенно появляться ПОД тающим
                        // звёздным полем, как и задумано ("снятие вуали").
                        unlockedSpaceContent
                            .transition(.identity)
                    }
                }
            }
        }
        .overlay {
            if onboardingViewModel.isActive {
                OnboardingView(onboardingViewModel: onboardingViewModel)
                    .transition(.opacity)
            }
        }
        // Плавные переходы: Desktop mode туда-обратно, лок/анлок.
        .animation(.easeOut(duration: 0.2), value: viewModel.desktopOverlay.isDesktopModeActive)
        .animation(.easeOut(duration: 0.2), value: viewModel.isActiveSpaceLocked)
        // Смена Space — без общего кросс-фейда всего блока: заметно
        // анимируется только уход старых карточек (asymmetric-transition на
        // каждой CardView ниже), а не "всё тает одним пятном".
        .animation(.easeOut(duration: 0.1), value: viewModel.activeSlot)
        .animation(.easeOut(duration: 0.25), value: onboardingViewModel.isActive)
        .onAppear {
            SettingsNavigation.shared.openWindowAction = openWindow
            onboardingViewModel.onFinish = { [viewModel] home, isFirstRun in
                if let home { viewModel.desktopOverlay.isEnabled = home == .desktop }
                if isFirstRun { CheatSheetCard.add(to: viewModel) }
            }
        }
        .background(
            WindowAccessor { overlayWindow.attach($0) }
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
            overlayWindow.apply()
        }
        // Синк с iCloud откладывает удалённые правки текста этой карточки,
        // пока в ней курсор (см. BoardViewModel.editingCardID).
        .onChange(of: textFocusedCardID) { _, id in
            viewModel.editingCardID = id
        }
        .onChange(of: viewModel.desktopOverlay.isEnabled) { _, _ in
            overlayWindow.apply()
        }
        .onChange(of: viewModel.desktopOverlay.isDesktopModeActive) { _, _ in
            overlayWindow.apply()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchWorkspace)) { notification in
            if let slot = notification.object as? Int, slot != viewModel.activeSlot {
                // Нельзя оставить "зависший" фокус на карточке со Space, с
                // которого только что ушли.
                setFocusedCard(nil)
                // Явный withAnimation здесь, а не только .animation(value:)
                // ниже — через GeometryReader → ZStack → ForEach декларативная
                // привязка по value надёжно анимирует уход старых карточек,
                // но не всегда подхватывает появление новых.
                withAnimation(.easeOut(duration: 0.1)) {
                    viewModel.switchWorkspace(to: slot)
                }
                onboardingViewModel.handle(.spaceSwitched)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lockCurrentSpace)) { _ in
            viewModel.lockActiveSpaceManually()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFocusCard)) { _ in
            guard !viewModel.isActiveSpaceLocked,
                  !viewModel.desktopOverlay.isDesktopModeActive,
                  !onboardingViewModel.isActive else { return }
            if focusedCardID != nil {
                setFocusedCard(nil)
            } else if let textFocusedCardID {
                setFocusedCard(textFocusedCardID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .replayOnboarding)) { _ in
            onboardingViewModel.start(currentHome: viewModel.desktopOverlay.isEnabled ? .desktop : .window)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cardWasMoved)) { _ in
            onboardingViewModel.handle(.cardMoved)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cardWasResized)) { _ in
            onboardingViewModel.handle(.cardResized)
        }
        .onReceive(NotificationCenter.default.publisher(for: .setCardTag)) { notification in
            guard let id = textFocusedCardID ?? focusedCardID,
                  let index = viewModel.cards.firstIndex(where: { $0.id == id }) else { return }
            let color = notification.object as? CardTagColor
            viewModel.cards[index].tagColor = color
            if color != nil { onboardingViewModel.handle(.tagColorSet) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cardTagColorWasSet)) { _ in
            onboardingViewModel.handle(.tagColorSet)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cardDidBecomeSpoiler)) { _ in
            onboardingViewModel.handle(.spoilerSet)
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestClearSpace)) { _ in
            isShowingClearSpaceConfirmation = true
        }
        .alert(
            "Clear \u{201C}\(viewModel.activeWorkspaceName)\u{201D}?",
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
                // Паттерн фона — здесь, а не в фоне окна (ThoughtsApp):
                // так он сам исчезает под Space Lock и в Desktop mode, где
                // unlockedSpaceContent не рендерится вовсе.
                CanvasPatternView(
                    pattern: viewModel.appearanceSettings.canvasPattern,
                    opacity: viewModel.appearanceSettings.patternOpacity
                )
                .frame(width: proxy.size.width, height: proxy.size.height)

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(canvasDragGesture(in: proxy.size))
                    .onTapGesture {
                        NotificationCenter.default.post(name: .clearTextSelection, object: nil)
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                    // Правый клик по пустому месту: карточка из шаблона — в точке клика.
                    .overlay {
                        CanvasContextMenu { template, point in
                            addCard(from: template, at: point, canvasSize: proxy.size)
                        }
                    }

                ForEach(viewModel.cards) { card in
                    let isFocused = card.id == focusedCardID
                    let displaySize = isFocused ? BoardViewModel.focusCardSize : card.size
                    let displayPosition = isFocused
                        ? BoardViewModel.focusOrigin(canvasSize: proxy.size, topInset: effectiveTopInset)
                        : BoardViewModel.clampedPosition(card.position, size: card.size, canvasSize: proxy.size, topInset: effectiveTopInset)

                    CardView(
                        card: card,
                        viewModel: viewModel,
                        canvasSize: proxy.size,
                        isInFocusMode: isFocused,
                        onTextFocusChange: { focused in
                            // "Чистим только если это всё ещё наше" — при
                            // переходе фокуса с карточки на карточку blur
                            // прежней может прийти ПОСЛЕ focus новой.
                            if focused {
                                textFocusedCardID = card.id
                            } else if textFocusedCardID == card.id {
                                textFocusedCardID = nil
                            }
                        },
                        onRequestExitFocus: { setFocusedCard(nil) },
                        isFocusTransitioning: card.id == focusTransitionCardID,
                        onPlacementPreviewChange: { preview in
                            placementPreviewTask?.cancel()
                            
                            if let preview {
                                var transaction = Transaction()
                                transaction.animation = nil
                                withTransaction(transaction) {
                                    placementPreview = preview
                                }
                                
                                placementPreviewTask = Task {
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
                    .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
                    // Подсказка над карточкой — снизу кнопка Ask AI и её
                    // панель (см. CardView). Привязка к НИЖНЕМУ краю со
                    // сдвигом на высоту карточки — не зависит от высоты подписи.
                    .overlay(alignment: .bottom) {
                        if isFocused && focusExitHint.isVisible {
                            // HintLabel фиксированно белый в обеих темах:
                            // лежит на затемнённой подложке, а не на фоне
                            // окна, так что .primary в светлой давал бы
                            // чёрный текст на тёмном.
                            HintLabel(text: "Click anywhere to exit Focus Mode")
                                .offset(y: -(displaySize.height + 12))
                        }
                    }
                    .offset(x: displayPosition.x, y: displayPosition.y)
                    // .compositingGroup() — карточка (стекло + текст +
                    // чат тега/кнопок) смешивается с тем, что позади, как
                    // один плоский слой при fade, а не покомпонентно;
                    // должно убрать серый след, который оставляло живое
                    // стекло при анимированном opacity.
                    .compositingGroup()
                    // Focus Mode: сфокусированная карточка поднимается над
                    // затемнением (zIndex 500 ниже), остальные гаснут, но
                    // НЕ выгружаются из дерева — в отличие от Space Lock
                    // это про визуальный шум, а не про приватность, и
                    // пересоздание карточек на выходе выглядело бы резче.
                    .zIndex(isFocused ? 1000 : 0)
                    .opacity(focusedCardID == nil || isFocused ? 1 : 0)
                    .allowsHitTesting(focusedCardID == nil || isFocused)
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
                
                // Затемнение под сфокусированной карточкой — ложится поверх
                // всех остальных слоёв канвы (zIndex по умолчанию 0) и под
                // саму карточку (1000). Клик по нему — один из трёх способов
                // выйти из Focus Mode, см. подпись под карточкой.
                if focusedCardID != nil {
                    Color.black.opacity(0.45)
                        .contentShape(Rectangle())
                        .onTapGesture { setFocusedCard(nil) }
                        .zIndex(500)
                        .transition(.opacity)
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
                
                // Зона перетаскивания окна — только в обычном режиме: в Desktop Overlay окно
                // закреплено на весь экран и двигаться не должно.
                if !viewModel.desktopOverlay.isEnabled {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: 76)
                        WindowDragArea()
                    }
                    .frame(height: effectiveTopInset)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            
            .coordinateSpace(name: "canvas")
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeOut(duration: 0.12), value: edgeHints.count)
            .animation(.easeInOut(duration: 0.28), value: focusedCardID)

            .onChange(of: proxy.size) { _, newValue in
                canvasSize = newValue
                viewModel.lastCanvasSize = newValue
            }
            .onAppear {
                canvasSize = proxy.size
                viewModel.lastCanvasSize = proxy.size
            }
        }
        .background(Color.clear)
        .overlay(alignment: .top) {
            SpaceToolbar(
                viewModel: viewModel,
                canvasSize: canvasSize,
                topInset: effectiveTopInset,
                isFocusModeActive: focusedCardID != nil,
                isOnboardingActive: onboardingViewModel.isActive
            )
            .padding(.top, workspacePillTopPadding)
            // В Focus Mode капсула Space скрыта целиком — она ломает
            // ощущение погружения, а её действия относятся ко всему Space,
            // не к сфокусированной карточке. Подсказки/hover-состояния
            // внутри неё лежат в этом же поддереве, так что гаснут вместе.
            .opacity(focusedCardID == nil ? 1 : 0)
            .allowsHitTesting(focusedCardID == nil)
            .animation(.easeInOut(duration: 0.28), value: focusedCardID)
        }
        .overlay(alignment: .center) {
            // Подсказка на пустом Space — по центру канвы. Та же
            // анимация "курсор растягивает карточку", что в шаге 1
            // интерактивного онбординга (см. CreateCardGestureIcon) —
            // единый визуальный язык, не два разных объяснения одного
            // жеста. Декоративная — allowsHitTesting(false), чтобы сам
            // драг создания карточки долетал до канвы под подсказкой.
            if emptyHint.isVisible && viewModel.cards.isEmpty {
                // opacity: 1 на самой подсказке — общее затемнение 0.4
                // ниже уже покрывает и иконку, и текст вместе, как одну
                // группу (задваивать прозрачность не нужно).
                VStack(spacing: 14) {
                    CreateCardGestureIcon()
                    HintLabel(text: "Drag anywhere to create your first card", color: AnyShapeStyle(.primary), opacity: 1)
                }
                .opacity(0.4)
                .allowsHitTesting(false)
                .transition(.opacity)
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
        .onChange(of: onboardingViewModel.isActive) { _, _ in
            updateEmptyHintState()
        }
        // Покрывает все входы и выходы сразу (Cmd+F, Escape, клик по фону,
        // смена Space) — все они меняют именно focusedCardID.
        .onChange(of: focusedCardID) { _, newValue in
            focusExitHint.cancel()
            guard newValue != nil else { return }
            focusExitHint.show(afterDelay: 3)
        }
    }

    private func updateEmptyHintState() {
        emptyHint.cancel()

        // Пока активен интерактивный тур, шаг 1 сам показывает "Drag
        // anywhere to create your first card" — без этого guard'а старая
        // подсказка всплыла бы поверх/рядом с ним через 2.5с и задублировала
        // тот же текст.
        guard !onboardingViewModel.isActive else { return }

        guard viewModel.cards.isEmpty else { return }

        emptyHint.show(afterDelay: 2.5)
    }

    /// В обычном окне — маленькая граница. В Desktop Overlay окно
    /// растянуто на весь экран, и карточки не должны упираться в самый
    /// верх/вырез камеры — там, где обычно сидят системные виджеты.
    private var effectiveTopInset: CGFloat {
        viewModel.desktopOverlay.isEnabled ? BoardViewModel.desktopOverlayTopInset : BoardViewModel.topCreationLimit
    }

    /// Плашка с именем Space — обычный SwiftUI-оверлей этой же канвы (не
    /// chrome окна), так что отступ под неё можно менять независимо от
    /// самого окна/frame — без компромисса с покрытием экрана, в отличие
    /// от системных элементов.
    private var workspacePillTopPadding: CGFloat {
        guard viewModel.desktopOverlay.isEnabled else { return 10 }
        return BoardViewModel.screenTopInset + 12
    }

    private func addCard(from template: CardTemplate, at point: CGPoint, canvasSize: CGSize) {
        let size = CGSize(width: BoardViewModel.snap(template.size.width), height: BoardViewModel.snap(template.size.height))
        let origin = BoardViewModel.clampedPosition(point, size: size, canvasSize: canvasSize, topInset: effectiveTopInset)
        let card = viewModel.addCard(at: origin, size: size, text: template.text)
        card.tagColor = template.tag
        newlyCreatedCardID = card.id
        guard template.isBoard else { return }
        // Карточка ещё монтируется — подсказка (CardView) чуть позже.
        let id = card.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            NotificationCenter.default.post(name: .boardTemplateCreated, object: id)
        }
    }

    private func canvasDragGesture(in canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("canvas"))
            .onChanged { value in
                // Затемнение поверх канвы и так перехватывает всё, пока
                // активен фокус — кроме драга, начатого ДО входа в него.
                guard focusedCardID == nil else { return }
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
                
                newlyCreatedCardID = viewModel.addCard(at: frame.origin, size: frame.size).id
                onboardingViewModel.handle(.cardCreated)
            }
    }

    /// Единственная точка смены фокуса. Флаг перехода обязан меняться в
    /// ТОМ ЖЕ обновлении, что и сам focusedCardID: если взводить его
    /// отдельным .onChange, он опаздывает на кадр, и контролы карточки
    /// успевают вернуться и проехать вместе с ней до конца анимации.
    private func setFocusedCard(_ id: UUID?) {
        guard focusedCardID != id else { return }
        focusTransitionTask?.cancel()
        focusTransitionCardID = id ?? focusedCardID
        focusedCardID = id
        focusTransitionTask = Task {
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            focusTransitionCardID = nil
        }
    }

}

#Preview {
    ContentView(viewModel: BoardViewModel())
        .frame(width: 900, height: 600)
}
