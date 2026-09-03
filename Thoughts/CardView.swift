import SwiftUI

struct CardView: View {
    @Bindable var card: Card
    var viewModel: BoardViewModel
    var canvasSize: CGSize
    var onPlacementPreviewChange: (CGRect?) -> Void
    var onEdgeHintsChange: ([EdgeHint]) -> Void
    
    @State private var dragOrigin: CGPoint?
    @State private var dragResizeSize: CGSize?
    @State private var isHovering = false
    @State private var isHoveringDeleteButton = false
    @State private var deleteProgress: CGFloat = 0.0
    @State private var isPressingDelete = false
    @State private var deleteTimer: Timer? = nil
    @State private var isShowingTagPopover = false
    @State private var isHoveringTagButton = false
    @State private var isRevealed = false
    @State private var relockTask: Task<Void, Never>? = nil // Таймер автоблокировки
    
    @FocusState private var isTextFocused: Bool
    
    private var pad: CGFloat { BoardViewModel.canvasSidePadding }
    private var topLimit: CGFloat { BoardViewModel.topCreationLimit }
    private var isPrivacyLocked: Bool {
        card.privacyMode != .none && !isRevealed
    }
    
    var body: some View {
        ZStack(alignment: SwiftUI.Alignment.topLeading) {
            // РОДНОЙ GLASS EFFECT:
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.clear)
                .glassEffect(in: .rect(cornerRadius: 16.0))
            
            // ТЕКСТОВЫЙ РЕДАКТОР
            TextEditor(text: $card.text)
                .font(.system(size: 15))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($isTextFocused)
                .scrollIndicators(.hidden)
                .padding(20)
                .scrollClipDisabled()
                .zIndex(0)
                .onChange(of: card.text) {
                    viewModel.scheduleDebouncedSave()
                    detectAndEnableLinks()
                }
                .onAppear {
                    detectAndEnableLinks()
                }
                .onChange(of: isTextFocused) { _, isFocused in
                    if isFocused {
                        cancelRelock()
                        viewModel.bringToFront(card)
                        NotificationCenter.default.post(name: NSNotification.Name("ClearTextSelection"), object: nil)
                    } else {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        if isRevealed {
                            scheduleRelock()
                        }
                    }
                }
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 15)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 15)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FocusNewCard"))) { notification in
                    if let targetID = notification.object as? UUID, targetID == card.id {
                        isTextFocused = true
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ClearTextSelection"))) { _ in
                    if let window = NSApp.keyWindow {
                        func clearSelectionInViews(subviews: [NSView]) {
                            for view in subviews {
                                if let textView = view as? NSTextView {
                                    textView.setSelectedRange(NSRange(location: 0, length: 0))
                                } else {
                                    clearSelectionInViews(subviews: view.subviews)
                                }
                            }
                        }
                        clearSelectionInViews(subviews: window.contentView?.subviews ?? [])
                    }
                }
            
            // ОВЕРЛЕЙ СПОЙЛЕРА И ЛОКА:
            if isPrivacyLocked {
                StarFieldOverlayView(mode: card.privacyMode) {
                    if card.privacyMode == .spoiler {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            isRevealed = true
                        }
                        if !isTextFocused { scheduleRelock() }
                    } else if card.privacyMode == .lock {
                        viewModel.authenticateWithTouchID { success in
                            if success {
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    isRevealed = true
                                }
                                if !isTextFocused { scheduleRelock() }
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
                        .fill(card.tagColor != nil ? card.tagColor!.color : Color.white.opacity(0.15))
                        .frame(width: 10, height: 10)
                        .scaleEffect(isHoveringTagButton ? 1.6 : 1.0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isPrivacyLocked)
            .onHover { inside in
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
            .opacity(card.tagColor != nil ? 1 : (isHovering && !isPrivacyLocked ? 1 : 0))
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHoveringTagButton)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .animation(.easeInOut(duration: 0.15), value: card.tagColor)
            .zIndex(104)
            
            // RESIZE HANDLE
            Path { path in
                path.move(to: CGPoint(x: 22, y: 14))
                path.addLine(to: CGPoint(x: 22, y: 14))
                path.addQuadCurve(
                    to: CGPoint(x: 14, y: 22),
                    control: CGPoint(x: 22, y: 22)
                )
                path.addLine(to: CGPoint(x: 14, y: 22))
            }
            .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
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
            .opacity(isHovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .zIndex(101)
            
            // DRAG HANDLE
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .frame(height: 25)
                .gesture(moveGesture)
                .zIndex(102)
                .onHover { inside in
                    if inside {
                        dragOrigin != nil ? NSCursor.closedHand.set() : NSCursor.openHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
            
            // КНОПКА УДАЛЕНИЯ
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isPressingDelete ? 0.15 : (isHoveringDeleteButton ? 0.08 : 0.0)))
                    .frame(width: 20, height: 20)
                    .animation(.easeIn(duration: 0.1), value: isHoveringDeleteButton)
                
                Circle()
                    .trim(from: 0.0, to: deleteProgress)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(-90))
                
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(isPressingDelete ? .red : .white.opacity(0.3))
            }
            .contentShape(Circle())
            .padding(5)
            .opacity(isHovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
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
        .frame(
            width: dragResizeSize?.width ?? card.size.width,
            height: dragResizeSize?.height ?? card.size.height
        )
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { _ in
                    viewModel.bringToFront(card)
                }
        )
        
        .animation(.easeInOut(duration: 0.35), value: isPrivacyLocked)
                .onChange(of: card.privacyMode) { _, newMode in
                    cancelRelock()
                    if newMode != .none {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            isRevealed = false
                        }
                    }
                }
            }
    
    // MARK: - Helper Methods & Gestures
    
    private func resetDeleteState() {
        isPressingDelete = false
        withAnimation(.none) {
            deleteProgress = 0.0
        }
        withAnimation(.easeOut(duration: 0.12)) {
            isPressingDelete = false
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
                
                let maxX = max(pad, canvasSize.width - pad - card.size.width)
                let maxY = max(topLimit, canvasSize.height - pad - card.size.height)
                
                card.position = CGPoint(
                    x: min(maxX, max(pad, origin.x + value.translation.width)),
                    y: min(maxY, max(topLimit, origin.y + value.translation.height))
                )
                
                if let preview = BoardViewModel.placementPreview(
                    movingId: card.id,
                    movingPosition: card.position,
                    movingSize: card.size,
                    others: viewModel.cards,
                    canvasSize: canvasSize
                ) {
                    onPlacementPreviewChange(CGRect(origin: preview, size: card.size))
                } else {
                    onPlacementPreviewChange(nil)
                }
                
                onEdgeHintsChange(
                    BoardViewModel.edgeHints(
                        movingPosition: card.position,
                        movingSize: card.size,
                        canvasSize: canvasSize
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
                    canvasSize: canvasSize
                ) {
                    withAnimation(.easeOut(duration: 0.12)) {
                        card.position = preview
                    }
                } else {
                    let snapped = BoardViewModel.snappedToEdges(
                        position: card.position,
                        size: card.size,
                        canvasSize: canvasSize
                    )
                    if snapped != card.position {
                        withAnimation(.easeOut(duration: 0.12)) {
                            card.position = snapped
                        }
                    }
                }
                
                onPlacementPreviewChange(nil)
                onEdgeHintsChange([])
                dragOrigin = nil
                viewModel.saveImmediately()
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
                dragResizeSize = nil
                viewModel.saveImmediately()
            }
    }
    
    private func detectAndEnableLinks() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow else { return }
            
            func scanViews(_ subviews: [NSView]) {
                for view in subviews {
                    if let textView = view as? NSTextView {
                        textView.isRichText = false
                        textView.importsGraphics = false
                        textView.isAutomaticLinkDetectionEnabled = true
                        textView.checkTextInDocument(nil)
                    } else {
                        scanViews(view.subviews)
                    }
                }
            }
            
            scanViews(window.contentView?.subviews ?? [])
        }
    }
    
    private func scheduleRelock() {
        relockTask?.cancel()
        relockTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 секунд
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isRevealed = false
                    }
                }
            }
        }
    }
    
    private func cancelRelock() {
        relockTask?.cancel()
        relockTask = nil
    }
}
