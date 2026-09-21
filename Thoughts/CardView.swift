import SwiftUI

struct CardView: View {
    @Bindable var card: Card
    var viewModel: BoardViewModel
    var canvasSize: CGSize
    /// Focus Mode (Cmd+F) — карточка отображается в едином фиксированном
    /// размере по центру канвы, остальные гаснут. Позиция/размер задаются
    /// снаружи (ContentView), сам `card` при этом не меняется.
    var isInFocusMode: Bool = false
    /// Текстовый курсор встал в эту карточку / ушёл из неё — ContentView
    /// по этому определяет, какую карточку фокусировать по Cmd+F.
    var onTextFocusChange: (Bool) -> Void = { _ in }
    var onRequestExitFocus: () -> Void = {}
    /// Карточка прямо сейчас едет в фокус или обратно. Приходит снаружи, а
    /// не считается локально по isInFocusMode: флаг обязан меняться в том
    /// же обновлении, что и сам фокус (см. ContentView.setFocusedCard).
    var isFocusTransitioning: Bool = false
    var onPlacementPreviewChange: (CGRect?) -> Void
    var onEdgeHintsChange: ([EdgeHint]) -> Void

    @State private var dragOrigin: CGPoint?
    @State private var dragResizeSize: CGSize?
    @State private var isHovering = false
    @State private var isHoveringDeleteButton = false
    @State private var deleteProgress: CGFloat = 0.0
    @State private var isPressingDelete = false
    @State private var isShowingTagPopover = false
    @State private var isHoveringTagButton = false
    @State private var isRevealed = false
    @State private var relockTask: Task<Void, Never>? = nil // Таймер автоблокировки после клика вне карточки
    @State private var isHighlighted = false
    @State private var unhighlightTask: Task<Void, Never>? = nil
    @State private var isGeneratingAI = false
    @State private var aiErrorMessage: String?
    // Панель Ask AI под карточкой — только в Focus Mode. Ответ не правит
    // текст карточки сам: он показывается под заданным вопросом, а что с
    // ним делать, решают кнопки Insert Below / Replace / Ask Again.
    @State private var isShowingCardAI = false
    @State private var cardAIQuestion = ""
    @State private var cardAIAnswer: String?
    @State private var cardAIPlaceholder = AICardPrompt.randomSuggestion()
    // Футер снимается СВОИМ состоянием, а не условием по isInFocusMode:
    // оно переключается внутри анимации ContentView, из-за чего кнопка
    // улетала вместе с уезжающей карточкой.
    @State private var isFocusFooterVisible = false
    // Ненавязчивая одноразовая подсказка про Cmd+F — см. .onChange(of:
    // card.text) ниже. hasShownFocusTipHint не даёт показать её больше
    // одного раза за время жизни этой CardView (новый релонч приложения
    // или новая карточка — снова доступно).
    @State private var focusTipHint = HintTimer()
    @State private var hasShownFocusTipHint = false
    // Одноразовая анимация появления карточки из Ask AI/Summarize —
    // "выскакивает" из-под нотча к своей итоговой позиции. См.
    // triggerAIPopInAnimationIfNeeded().
    @State private var aiPopInOffset: CGSize = .zero
    @State private var aiPopInScale: CGFloat = 1.0
    
    @State private var isTextFocused: Bool = false
    // @GestureState, а не @State: должен сбрасываться самой системой жестов
    // при завершении/прерывании попытки, а не только через .onEnded — иначе
    // при перестановке карточки в bringToFront (меняет z-порядок в ZStack,
    // что может физически переносить NSView в иерархии AppKit) распознаватель
    // текущего жеста мог прерваться ДО onEnded, и обычный @State застревал
    // в true навсегда, из-за чего повторные клики по этой карточке больше
    // не поднимали её.
    @GestureState private var hasSignaledGestureStart = false

    private var pad: CGFloat { BoardViewModel.canvasSidePadding }
    private var effectiveTopInset: CGFloat {
        viewModel.desktopOverlay.isEnabled ? BoardViewModel.desktopOverlayTopInset : BoardViewModel.topCreationLimit
    }
    private var isPrivacyLocked: Bool {
        card.privacyMode != .none && !isRevealed
    }
    // Пока в карточке активен текстовый курсор, элементы управления не
    // должны пропадать при уводе указателя мыши за пределы карточки —
    // иначе непонятно, как удалить/изменить размер уже сфокусированной
    // карточки, не кликнув по ней снова.
    private var showsHoverControls: Bool {
        isHovering || isTextFocused
    }
    private var isAIHighlighted: Bool {
        viewModel.aiHighlightedCardIDs.contains(card.id)
    }
    /// Контролы карточки скрыты и в самом фокусе, и всю дорогу туда-обратно:
    /// иначе на выходе они возвращаются в первом же кадре и едут вместе со
    /// сжимающейся карточкой до конца анимации.
    private var isFocusHidden: Bool {
        isInFocusMode || isFocusTransitioning
    }
    /// В Focus Mode размер продиктован фокусом, а не моделью/драгом.
    private var effectiveSize: CGSize {
        guard !isInFocusMode else { return BoardViewModel.focusCardSize }
        return CGSize(
            width: dragResizeSize?.width ?? card.size.width,
            height: dragResizeSize?.height ?? card.size.height
        )
    }
    private var cardAIAnimation: Animation { .easeInOut(duration: 0.22) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Liquid Glass + тонкий чёрный тон поверх — см. CardSurfaceStyle.swift.
            CardSurfaceBackground()

            // Реальный текст не создаётся вообще, пока карточка скрыта под
            // Spoiler/Lock — иначе при малой степени Liquid Glass (слайдер
            // в Settings → Appearance в macOS 27) содержимое может
            // просвечивать сквозь полупрозрачный StarFieldOverlayView,
            // который лишь визуально накрывает уже отрисованный текст.
            // Тот же принцип, что уже применён к заблокированному Space
            // целиком (см. ContentView.swift — ForEach с карточками не
            // создаётся вовсе, пока Space заблокирован).
            if !isPrivacyLocked {
                CardTextView(
                    text: $card.text,
                    formattingData: $card.formattingData,
                    isFocused: $isTextFocused,
                    cardSize: effectiveSize,
                    onTextChange: {
                        viewModel.scheduleDebouncedSave()
                    },
                    onFocusChange: { focused in
                        if focused {
                            viewModel.bringToFront(card)
                        }
                    },
                    onAIAction: handleAIAction,
                    onEscape: isInFocusMode ? onRequestExitFocus : nil
                )
                .opacity(isFocusTransitioning ? 0 : 1)
                // Асимметрично и намеренно: прячем мгновенно (иначе текст
                // остаётся полупрозрачно видимым ровно те кадры, пока
                // NSTextView переверстывается под новую ширину — ради чего
                // всё и затевалось), возвращаем мягким fade, когда карточка
                // уже встала. nil здесь перебивает анимацию канвы из
                // ContentView, которая иначе растянула бы скрытие на весь
                // переход — тот же приём, что у точки тега ниже.
                .animation(isFocusTransitioning ? nil : .easeIn(duration: 0.15), value: isFocusTransitioning)
                .zIndex(0)
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 15)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 15)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .focusNewCard)) { notification in
                    if let targetID = notification.object as? UUID, targetID == card.id {
                        isTextFocused = true
                    }
                }
            }

            // ОВЕРЛЕЙ СПОЙЛЕРА И ЛОКА:
            if isPrivacyLocked {
                StarFieldOverlayView(mode: card.privacyMode) {
                    if card.privacyMode == .spoiler {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            isRevealed = true
                        }
                    } else if card.privacyMode == .lock {
                        viewModel.authenticateWithTouchID { success in
                            if success {
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    isRevealed = true
                                }
                            }
                        }
                    }
                }
                // Плавный проявляющийся переход с легким масштабированием
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(99)
            }
            
            // КНОПКА ТЕГА
            Button {
                guard !isPrivacyLocked else { return }
                isShowingTagPopover.toggle()
            } label: {
                ZStack {
                    Color.clear
                        .frame(width: 16, height: 16)
                    
                    Circle()
                        .fill(card.tagColor != nil ? card.tagColor!.color : Color.white.opacity(0.25))
                        .frame(width: 10, height: 10)
                        .scaleEffect(isHoveringTagButton && !isPrivacyLocked ? 1.6 : 1.0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Не .disabled(isPrivacyLocked) — SwiftUI/AppKit сам приглушает
            // внешний вид отключённой кнопки (не связано с zIndex/порядком
            // отрисовки, из-за этого точка тега выглядела тусклой на
            // заблокированной карточке). allowsHitTesting блокирует клик,
            // но НЕ саму hover-детекцию (.onHover на macOS работает через
            // отдельный tracking area) — поэтому её тоже нужно игнорировать
            // отдельно ниже, иначе точка продолжает увеличиваться при
            // наведении на заблокированной карточке, создавая ложное
            // ощущение, что по ней можно нажать.
            .allowsHitTesting(!isPrivacyLocked && !isInFocusMode)
            .onHover { inside in
                guard !isPrivacyLocked, !isInFocusMode else { return }
                isHoveringTagButton = inside
                if inside {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .popover(isPresented: $isShowingTagPopover, arrowEdge: .bottom) {
                TagPopoverView(selectedColor: $card.tagColor, privacyMode: $card.privacyMode) {
                    isShowingTagPopover = false
                    viewModel.saveImmediately()
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .opacity(isFocusHidden ? 0 : (card.tagColor != nil ? 1 : (showsHoverControls && !isPrivacyLocked ? 1 : 0)))
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHoveringTagButton)
            .animation(.easeInOut(duration: 0.15), value: showsHoverControls)
            .animation(.easeInOut(duration: 0.15), value: card.tagColor)
            // Мгновенно, без доигрывания: иначе точка тянется к новому углу
            // вместе с карточкой, пока идёт анимация ContentView.
            .animation(nil, value: isFocusHidden)
            // Выше оверлея Spoiler/Lock (zIndex 99), чтобы точка тега была
            // видна поверх тонировки, а не под ней.
            .zIndex(105)

            // AI-БЕЙДЖ — постоянный (не зависит от hover/isPrivacyLocked, в
            // отличие от точки тега выше), ровно в том же месте, что точка
            // тега, но выше по zIndex. allowsHitTesting(false) — клик
            // проходит насквозь на кнопку тега под ним. См. Card.isAIGenerated.
            if card.isAIGenerated && !isFocusHidden {
                Image(systemName: "sparkle")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .padding(9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(false)
                    .transition(.identity)
                    .zIndex(100)
            }

            // RESIZE HANDLE и DRAG HANDLE — в Focus Mode не создаются вовсе:
            // позиция и размер там продиктованы фокусом, а не моделью, так
            // что двигать/тянуть карточку нечем. Не просто opacity(0):
            // .onHover на macOS работает и у скрытых через hit-testing view,
            // и невидимый хендл всё равно менял бы курсор.
            if !isFocusHidden {
                Path { path in
                    path.move(to: CGPoint(x: 22, y: 14))
                    path.addLine(to: CGPoint(x: 22, y: 14))
                    path.addQuadCurve(
                        to: CGPoint(x: 14, y: 22),
                        control: CGPoint(x: 22, y: 22)
                    )
                    path.addLine(to: CGPoint(x: 14, y: 22))
                }
                .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside {
                        let selector = NSSelectorFromString("_windowResizeNorthWestSouthEastCursor")
                        if NSCursor.responds(to: selector) {
                            if let customCursor = NSCursor.perform(selector)?.takeUnretainedValue() as? NSCursor {
                                customCursor.set()
                            }
                        }
                    } else {
                        NSCursor.pop()
                        NSCursor.arrow.set()
                    }
                }
                .gesture(resizeGesture)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .opacity(showsHoverControls ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: showsHoverControls)
                // .identity — исчезать при входе в фокус нужно мгновенно, а
                // не доигрывать fade, растягиваясь вместе с карточкой (тот
                // же приём, что у карточек при блокировке Space).
                .transition(.identity)
                .zIndex(101)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .frame(height: 25)
                    .gesture(moveGesture)
                    .transition(.identity)
                    .zIndex(102)
                    .onHover { inside in
                        if inside {
                            dragOrigin != nil ? NSCursor.closedHand.set() : NSCursor.arrow.set()
                        }
                    }
            }

            // КНОПКА УДАЛЕНИЯ
            if !isPrivacyLocked && !isFocusHidden {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(isPressingDelete ? 0.22 : (isHoveringDeleteButton ? 0.14 : 0.0)))
                        .frame(width: 20, height: 20)
                        .animation(.easeIn(duration: 0.1), value: isHoveringDeleteButton)
                    
                    Circle()
                        .trim(from: 0.0, to: deleteProgress)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(-90))
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(isPressingDelete ? Color.red : Color.white.opacity(0.4))
                }
                .contentShape(Circle())
                .padding(5)
                .opacity(showsHoverControls ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: showsHoverControls)
                .transition(.identity)
                .zIndex(103)
                .onHover { inside in
                    isHoveringDeleteButton = inside
                    if inside {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 10, perform: {
                    Task { @MainActor in
                        viewModel.deleteCard(card)
                        NSCursor.arrow.set()
                        resetDeleteState()
                    }
                }, onPressingChanged: { pressing in
                    if pressing {
                        isPressingDelete = true
                        withAnimation(.linear(duration: 0.5)) {
                            deleteProgress = 1.0
                        }
                    } else {
                        resetDeleteState()
                    }
                })
            }

            // ПОДСВЕТКА ПРИ ПЕРЕХОДЕ ИЗ SPOTLIGHT / НОВОЙ AI-КАРТОЧКИ
            // Spotlight — временная (гаснет через 1.6с, см. .highlightCard
            // ниже); AI — постоянная, пока карточку явно не кликнут (см.
            // aiHighlightedCardIDs, снимается в gesture ниже).
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity((isHighlighted || isAIHighlighted) ? 0.9 : 0), lineWidth: 2)
                .shadow(color: .white.opacity((isHighlighted || isAIHighlighted) ? 0.7 : 0), radius: (isHighlighted || isAIHighlighted) ? 16 : 0)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.3), value: isAIHighlighted)
                .zIndex(106)

            // ИНДИКАТОР AI-ЗАПРОСА
            if isGeneratingAI {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.black.opacity(0.25))
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(107)
            }
        }
        .frame(width: effectiveSize.width, height: effectiveSize.height)
        // Футер Focus Mode — кнопка "Ask AI…", разворачивающаяся в панель
        // во всю ширину карточки. Привязка к ВЕРХНЕМУ краю плюс сдвиг на
        // высоту карточки: так положение не зависит от собственной высоты
        // футера, которая скачет между кнопкой и раскрытой панелью
        // (alignmentGuide внутри overlay это не решает).
        .overlay(alignment: .top) {
            if isFocusFooterVisible {
                Group {
                    if isShowingCardAI {
                        cardAskAIPanel
                    } else {
                        askAIButton
                    }
                }
                // Именно focusCardSize, а не effectiveSize: футер живёт
                // только в фокусе, а на выходе effectiveSize уже вернулся
                // к размеру карточки и сдвиг поехал бы вместе с ней.
                .offset(y: BoardViewModel.focusCardSize.height + 12)
            }
        }
        // Подсказка про Cmd+F во время печати в обычной карточке — над
        // самой карточкой, мелким полупрозрачным текстом, не мешает
        // печатать (allowsHitTesting(false), не блокирующий элемент).
        .overlay(alignment: .top) {
            if focusTipHint.isVisible {
                // .primary, а не дефолтный белый у HintLabel — этот хинт
                // висит прямо над обычной карточкой на фоне канвы, не
                // поверх затемнения (в отличие от подсказки выхода из
                // Focus Mode), так что фиксированный белый в светлой теме
                // был бы нечитаем — та же причина, что у подсказки
                // пустого Space.
                HintLabel(text: "Try \u{2318}F to focus this card", fontSize: 10, color: AnyShapeStyle(.primary), opacity: 0.5)
                    .offset(y: -22)
            }
        }
        .scaleEffect(aiPopInScale)
        .offset(aiPopInOffset)
        .onAppear { triggerAIPopInAnimationIfNeeded() }
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($hasSignaledGestureStart) { _, state, _ in
                    guard !state else { return }
                    state = true
                    viewModel.bringToFront(card)
                    viewModel.aiHighlightedCardIDs.remove(card.id)
                    NotificationCenter.default.post(name: .cardWasClicked, object: card.id)
                }
        )

        .animation(.easeInOut(duration: 0.35), value: isPrivacyLocked)
        .animation(.easeInOut(duration: 0.15), value: isGeneratingAI)
        .onChange(of: isTextFocused) { _, focused in
            onTextFocusChange(focused)
            // Клик обратно в текст карточки закрывает панель Ask AI: пока
            // она открыта, курсор живёт в её собственном поле, так что
            // возврат фокуса сюда — однозначный сигнал "я снова пишу".
            if focused, isShowingCardAI {
                collapseCardAI()
            }
        }
        .onChange(of: isInFocusMode) { _, active in
            if !active { collapseCardAI() }
            // Футер гаснет тем же fade, что и появлялся, только быстрее —
            // он привязан к карточке, а она в этот момент уже уезжает.
            withAnimation(.easeOut(duration: 0.12)) { isFocusFooterVisible = false }
            if active {
                // Подсказка про Cmd+F теряет смысл ровно в момент, когда
                // Cmd+F уже нажали — не даём ей доиграть поверх входа в фокус.
                focusTipHint.cancel()
            }
        }
        // Срабатывает только на реальный переход через порог во время
        // печати в этой сессии — .onChange не триггерится на начальное
        // значение при монтировании, так что открытие уже длинной
        // существующей карточки подсказку не покажет.
        .onChange(of: card.text) { oldValue, newValue in
            guard !isInFocusMode, !hasShownFocusTipHint,
                  oldValue.count < Self.focusTipThreshold, newValue.count >= Self.focusTipThreshold else { return }
            hasShownFocusTipHint = true
            focusTipHint.show(holdFor: Self.focusTipHoldDuration)
        }
        // Переход закончился — карточка встала на место. Только теперь
        // возвращаем то, что прятали на время движения.
        .onChange(of: isFocusTransitioning) { _, transitioning in
            guard !transitioning, isInFocusMode else { return }
            withAnimation(.easeIn(duration: 0.15)) { isFocusFooterVisible = true }
        }
        // Escape, когда текст карточки НЕ в фокусе (например, курсор ушёл в
        // поле Ask AI или карточку просто не редактируют). Случай "текст в
        // фокусе" перехватывается раньше, в CardNSTextView.cancelOperation —
        // NSTextView не пропускает Escape дальше по цепочке сам.
        .onExitCommand(perform: isInFocusMode ? onRequestExitFocus : nil)
        .alert("AI Error", isPresented: Binding(
            get: { aiErrorMessage != nil },
            set: { if !$0 { aiErrorMessage = nil } }
        )) {
            Button("OK") { aiErrorMessage = nil }
        } message: {
            Text(aiErrorMessage ?? "")
        }
                .onChange(of: card.privacyMode) { _, newMode in
                    cancelRelock()
                    if newMode != .none {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            isRevealed = false
                        }
                    }
                }
                // Раскрытая по клику на спойлер/лок карточка остаётся
                // активной, пока пользователь не кликнет вне неё — на пустой
                // холст (ClearTextSelection) или на другую карточку
                // (cardWasClicked с чужим id). Сама блокировка при этом не
                // мгновенная, а с 5-секундной отсрочкой — успеешь кликнуть
                // обратно на эту же карточку и блокировка отменится.
                .onReceive(NotificationCenter.default.publisher(for: .clearTextSelection)) { _ in
                    if isRevealed {
                        scheduleRelock()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .cardWasClicked)) { notification in
                    guard let clickedID = notification.object as? UUID else { return }
                    if clickedID == card.id {
                        cancelRelock()
                    } else if isRevealed {
                        scheduleRelock()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .highlightCard)) { notification in
                    guard let targetID = notification.object as? UUID, targetID == card.id else { return }
                    viewModel.bringToFront(card)
                    unhighlightTask?.cancel()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isHighlighted = true
                    }
                    unhighlightTask = Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isHighlighted = false
                        }
                    }
                }
            }
    
    // MARK: - Ask AI внутри карточки (Focus Mode)

    private var askAIButton: some View {
        Button {
            // Пока пользователь печатал в самой карточке, её текстовое
            // поле удерживает first responder — панель Ask AI должна
            // явно получить его, а не соревноваться за фокус в тот же
            // момент. isTextFocused = false тем же путём, что и обычная
            // потеря фокуса, уводит первый respond'ер с CardTextView.
            isTextFocused = false
            cardAIPlaceholder = AICardPrompt.randomSuggestion()
            withAnimation(cardAIAnimation) { isShowingCardAI = true }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkle")
                    .font(.system(size: 10))
                Text("Ask AI\u{2026}")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .transition(.opacity)
    }

    /// Тот же визуальный язык, что у ContentView.askAIPanel, но скоуп —
    /// ровно эта карточка, и по ширине панель совпадает с ней. Фиксированных
    /// инструментов здесь нет: Summarize/Rewrite/… остались в контекстном
    /// меню текста (правый клик → AI), а тут — свободная формулировка,
    /// подсказанная примером в пустом поле.
    private var cardAskAIPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let answer = cardAIAnswer {
                Text(cardAIQuestion)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)

                ScrollView {
                    Text(answer)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundStyle(Color.white.opacity(0.88))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                }
                .frame(height: 150)
                // Гасится сам текст, а не подкладывается плашка сверху —
                // тогда край гарантированно сходится с фоном панели, каким
                // бы он ни был. Тот же приём уже используется у текста
                // карточки (CardTextView в body выше).
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.82),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                cardAIActionBar(for: answer)
            } else {
                AIPromptTextView(text: $cardAIQuestion, shouldFocus: isShowingCardAI) {
                    askCardAI()
                }
                .frame(height: 96)
                .overlay(alignment: .topLeading) {
                    if cardAIQuestion.isEmpty {
                        Text(cardAIPlaceholder)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .padding(.leading, 11)
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 8) {
                        if isGeneratingAI {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Button {
                            askCardAI()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 22))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.white.opacity(0.85))
                        .disabled(isGeneratingAI || cardAIQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: BoardViewModel.focusCardSize.width)
        .background(
            CardSurfaceBackground(
                cornerRadius: 16,
                usesGlassEffect: false,
                tintOpacity: 0.15,
                materialStyle: .thickMaterial,
                lightMaterialStyle: .ultraThinMaterial,
                lightTintOpacity: 0.2
            )
        )
        .transition(.opacity)
    }

    /// Собственного фона у панели действий нет — она лежит прямо на фоне
    /// всей панели Ask AI, поэтому цвет совпадает с ним по определению, и
    /// нижние скругления панели ничем не перекрываются.
    private func cardAIActionBar(for answer: String) -> some View {
        HStack(spacing: 10) {
            cardAIChip(title: "Insert Below", systemImage: "text.insert") {
                card.text += (card.text.isEmpty ? "" : "\n\n") + answer
                viewModel.scheduleDebouncedSave()
                collapseCardAI()
            }
            cardAIChip(title: "Replace", systemImage: "arrow.triangle.2.circlepath") {
                card.text = answer
                viewModel.scheduleDebouncedSave()
                collapseCardAI()
            }
            cardAIChip(title: "Ask Again", systemImage: "arrow.counterclockwise") {
                cardAIAnswer = nil
                cardAIQuestion = ""
                cardAIPlaceholder = AICardPrompt.randomSuggestion()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .padding(.horizontal, 18)
    }

    private func cardAIChip(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }

    /// Результат НЕ попадает в карточку сам — показывается под вопросом,
    /// пользователь сам решает, дописать его, заменить им текст или
    /// спросить заново.
    private func askCardAI() {
        let question = cardAIQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isGeneratingAI else { return }
        let context = card.text
        isGeneratingAI = true
        Task {
            do {
                let service = try AITextServiceFactory.makeActiveService()
                let userText = context.isEmpty ? question : "Note:\n\(context)\n\nRequest: \(question)"
                let result = try await service.generate(
                    systemPrompt: AICardPrompt.systemPrompt,
                    userText: userText
                )
                await MainActor.run {
                    cardAIAnswer = result
                    isGeneratingAI = false
                }
            } catch {
                await MainActor.run {
                    aiErrorMessage = error.localizedDescription
                    isGeneratingAI = false
                }
            }
        }
    }

    private func collapseCardAI() {
        withAnimation(cardAIAnimation) { isShowingCardAI = false }
        cardAIQuestion = ""
        cardAIAnswer = nil
    }

    // MARK: - Подсказка "Try Cmd+F"

    private static let focusTipThreshold = 60
    /// Втрое дольше исходных 1.5с — не успевали прочитать.
    private static let focusTipHoldDuration: Double = 4.5

    // MARK: - Helper Methods & Gestures

    private func resetDeleteState() {
        isPressingDelete = false
        withAnimation(.easeOut(duration: 0.12)) {
            deleteProgress = 0.0
        }
    }
    
    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = card.position
                    viewModel.bringToFront(card)
                    NSCursor.closedHand.set()
                }
                guard let origin = dragOrigin else { return }

                card.position = BoardViewModel.clampedPosition(
                    CGPoint(x: origin.x + value.translation.width, y: origin.y + value.translation.height),
                    size: card.size,
                    canvasSize: canvasSize,
                    topInset: effectiveTopInset
                )
                
                if let preview = BoardViewModel.placementPreview(
                    movingId: card.id,
                    movingPosition: card.position,
                    movingSize: card.size,
                    others: viewModel.cards,
                    canvasSize: canvasSize,
                    topInset: effectiveTopInset
                ) {
                    onPlacementPreviewChange(CGRect(origin: preview, size: card.size))
                } else {
                    onPlacementPreviewChange(nil)
                }

                onEdgeHintsChange(
                    BoardViewModel.edgeHints(
                        movingPosition: card.position,
                        movingSize: card.size,
                        canvasSize: canvasSize,
                        topInset: effectiveTopInset
                    )
                )
            }
            .onEnded { _ in
                NSCursor.openHand.set()
                if let preview = BoardViewModel.placementPreview(
                    movingId: card.id,
                    movingPosition: card.position,
                    movingSize: card.size,
                    others: viewModel.cards,
                    canvasSize: canvasSize,
                    topInset: effectiveTopInset
                ) {
                    withAnimation(.easeOut(duration: 0.12)) {
                        card.position = preview
                    }
                } else {
                    let snapped = BoardViewModel.snappedToEdges(
                        position: card.position,
                        size: card.size,
                        canvasSize: canvasSize,
                        topInset: effectiveTopInset
                    )
                    if snapped != card.position {
                        withAnimation(.easeOut(duration: 0.12)) {
                            card.position = snapped
                        }
                    }
                }
                
                onPlacementPreviewChange(nil)
                onEdgeHintsChange([])
                // dragOrigin ставится только в onChanged реального драга — если
                // он не nil, значит карточку и правда подвинули (не просто
                // кликнули), см. OnboardingViewModel.handle(.cardMoved).
                if dragOrigin != nil {
                    NotificationCenter.default.post(name: .cardWasMoved, object: nil)
                }
                dragOrigin = nil
                viewModel.saveGeometry()
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                if dragResizeSize == nil {
                    viewModel.bringToFront(card)
                }
                
                let maxWidth = max(BoardViewModel.minCardSize, canvasSize.width - pad - card.position.x)
                let maxHeight = max(BoardViewModel.minCardSize, canvasSize.height - pad - card.position.y)
                
                dragResizeSize = CGSize(
                    width: min(maxWidth, max(BoardViewModel.minCardSize, card.size.width + value.translation.width)),
                    height: min(maxHeight, max(BoardViewModel.minCardSize, card.size.height + value.translation.height))
                )
            }
            .onEnded { _ in
                NSCursor.pop()
                NSCursor.arrow.set()
                guard let size = dragResizeSize else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    card.size = CGSize(
                        width: BoardViewModel.snap(size.width),
                        height: BoardViewModel.snap(size.height)
                    )
                }
                NotificationCenter.default.post(name: .cardWasResized, object: nil)
                dragResizeSize = nil
                viewModel.saveGeometry()
            }
    }

    private func scheduleRelock() {
        // Не перезапускаем уже идущий отсчёт — иначе клик по любой ДРУГОЙ
        // карточке (не только по этой) продлевал бы 5 секунд заново на
        // каждый такой клик, и таймер практически никогда не срабатывал бы.
        // Отсчёт должен идти независимо с момента первого "клика в сторону"
        // и сбрасываться только явным cancelRelock() при возврате фокуса
        // именно на эту карточку.
        guard relockTask == nil else { return }
        relockTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 секунд
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Естественное срабатывание (не отмена через cancelRelock)
                // тоже должно обнулить relockTask — иначе guard выше
                // навсегда блокировал бы повторный запуск таймера при
                // следующем раскрытии этой же карточки.
                relockTask = nil
                withAnimation(.easeInOut(duration: 0.3)) {
                    isRevealed = false
                }
            }
        }
    }

    private func cancelRelock() {
        relockTask?.cancel()
        relockTask = nil
    }

    // MARK: - AI actions (см. Thoughts/AI)

    /// Играется один раз при появлении карточки, созданной Ask AI/Summarize
    /// (см. aiHighlightedCardIDs) — стартует из точки под нотчем (там же,
    /// где сама панель Ask AI) и с уменьшенным масштабом, затем пружинно
    /// анимируется к настоящей позиции/масштабу карточки.
    private func triggerAIPopInAnimationIfNeeded() {
        guard viewModel.aiHighlightedCardIDs.contains(card.id) else { return }

        let finalPosition = BoardViewModel.clampedPosition(
            card.position, size: card.size, canvasSize: canvasSize, topInset: effectiveTopInset
        )
        let notchOrigin = CGPoint(x: canvasSize.width / 2 - card.size.width / 2, y: -card.size.height * 0.6)

        aiPopInOffset = CGSize(width: notchOrigin.x - finalPosition.x, height: notchOrigin.y - finalPosition.y)
        aiPopInScale = 0.35
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            aiPopInOffset = .zero
            aiPopInScale = 1.0
        }
    }

    private func handleAIAction(_ action: AITextAction, _ inputText: String) {
        // Не даём запустить второй запрос поверх ещё не завершённого —
        // результат первого мог бы перезаписать то, что успел напечатать
        // пользователь, пока ждал второй.
        guard !isGeneratingAI, !inputText.isEmpty else { return }
        isGeneratingAI = true
        Task {
            do {
                let service = try AITextServiceFactory.makeActiveService()
                let result = try await service.generate(systemPrompt: action.systemPrompt, userText: inputText)
                await MainActor.run {
                    if action.appendsResult {
                        card.text += (card.text.isEmpty ? "" : "\n\n") + result
                    } else {
                        card.text = result
                    }
                    viewModel.scheduleDebouncedSave()
                    isGeneratingAI = false
                }
            } catch {
                await MainActor.run {
                    aiErrorMessage = error.localizedDescription
                    isGeneratingAI = false
                }
            }
        }
    }
}
