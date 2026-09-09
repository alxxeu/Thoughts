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

    var body: some View {
        Group {
            if viewModel.isActiveSpaceLocked {
                // Полностью отдельная ветка дерева: карточки и canvas этого
                // Space physически не существуют, пока он заблокирован —
                // то же самое "выгружение", что происходит при обычном
                // переключении между Spaces (ForEach(viewModel.cards) для
                // невыбранного слота тоже не рендерится). Никакого
                // отдельного blur-слоя поверх живого контента не нужно.
                SpaceLockOverlayView(viewModel: viewModel)
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
        .animation(.easeOut(duration: 0.25), value: isShowingOnboarding)
        .onReceive(NotificationCenter.default.publisher(for: .switchWorkspace)) { notification in
            if let slot = notification.object as? Int {
                viewModel.switchWorkspace(to: slot)
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
            "Clear \u{201C}\(viewModel.activeWorkspace?.name ?? "Space \(viewModel.activeSlot)")\u{201D}?",
            isPresented: $isShowingClearSpaceConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All Cards", role: .destructive) {
                viewModel.clearActiveSpace()
            }
        } message: {
            Text("This will permanently delete all \(viewModel.cards.count) card\(viewModel.cards.count == 1 ? "" : "s") in this Space. This can\u{2019}t be undone.")
        }
    }

    private var unlockedSpaceContent: some View {
        GeometryReader { proxy in
            ZStack(alignment: SwiftUI.Alignment.topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(canvasDragGesture(in: proxy.size))
                    .onTapGesture {
                        NotificationCenter.default.post(name: NSNotification.Name("ClearTextSelection"), object: nil)
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }

                ForEach(viewModel.cards) { card in
                    let adaptedPosition = adaptivePosition(for: card, in: proxy.size)
                    
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
                    .frame(width: card.size.width, height: card.size.height, alignment: SwiftUI.Alignment.topLeading)
                    .offset(x: adaptedPosition.x, y: adaptedPosition.y)
                    .onAppear {
                        if newlyCreatedCardID == card.id {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                NotificationCenter.default.post(name: NSNotification.Name("FocusNewCard"), object: card.id)
                                newlyCreatedCardID = nil
                            }
                        }
                    }
                }
                
                if let placementPreview {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.05))
                        .frame(width: placementPreview.width, height: placementPreview.height, alignment: SwiftUI.Alignment.topLeading)
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
                            .frame(width: frame.width, height: frame.height, alignment: SwiftUI.Alignment.topLeading)
                            .offset(x: frame.minX, y: frame.minY)
                            .allowsHitTesting(false)
                            .transition(AnyTransition.opacity)
                        
                    case .corner(let corner, let frame):
                        CornerBracket(corner: corner)
                            .stroke(
                                Color.primary.opacity(0.3),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                            )
                            .blur(radius: 1)
                            .frame(width: frame.width, height: frame.height, alignment: SwiftUI.Alignment.topLeading)
                            .offset(x: frame.minX, y: frame.minY)
                            .allowsHitTesting(false)
                            .transition(AnyTransition.opacity)
                    }
                }
                
                if let draftFrame {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: draftFrame.width, height: draftFrame.height, alignment: SwiftUI.Alignment.topLeading)
                        .offset(x: draftFrame.minX, y: draftFrame.minY)
                        .allowsHitTesting(false)
                }
                
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: 76)
                    WindowDragArea()
                }
                .frame(height: BoardViewModel.topCreationLimit)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            
            .coordinateSpace(name: "canvas")
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeOut(duration: 0.12), value: edgeHints.count)
            
            .onChange(of: proxy.size) { _, _ in
                isWindowResizing = true
                
                resizeDebounceTask?.cancel()
                resizeDebounceTask = Task {
                    try? await Task.sleep(for: .seconds(0.15))
                    guard !Task.isCancelled else { return }
                    isWindowResizing = false
                }
            }
        }
        .background(Color.clear)
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                Group {
                    if isEditingWorkspaceName {
                        TextField("Space name", text: $workspaceNameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.85))
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
                        Text(viewModel.activeWorkspace?.name ?? "Space \(viewModel.activeSlot)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.5))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .contentShape(Capsule())
                .onTapGesture {
                    if !isEditingWorkspaceName {
                        startWorkspaceRename()
                    }
                }
                
                // Текст подсказки
                if showEmptyHint && viewModel.cards.isEmpty {
                    Text("Drag anywhere to create your first card")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.primary.opacity(0.3))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.top, 10)
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

    private func adaptivePosition(for card: Card, in canvasSize: CGSize) -> CGPoint {
        let pad = BoardViewModel.canvasSidePadding
        let topLimit = BoardViewModel.topCreationLimit
        
        let maxX = max(pad, canvasSize.width - pad - card.size.width)
        let maxY = max(topLimit, canvasSize.height - pad - card.size.height)
        
        let displayX = min(card.position.x, maxX)
        let displayY = min(card.position.y, maxY)
        
        return CGPoint(x: displayX, y: displayY)
    }

    private func canvasDragGesture(in canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("canvas"))
            .onChanged { value in
                NotificationCenter.default.post(name: NSNotification.Name("ClearTextSelection"), object: nil)
                NSApp.keyWindow?.makeFirstResponder(nil)
                if creationStart == nil {
                    creationStart = clamped(value.startLocation, in: canvasSize)
                }
                guard let start = creationStart else { return }
                let current = clamped(value.location, in: canvasSize)

                let origin = CGPoint(x: min(start.x, current.x), y: min(start.y, current.y))
                let size = CGSize(
                    width: max(BoardViewModel.minCardSize, abs(current.x - start.x)),
                    height: max(BoardViewModel.minCardSize, abs(current.y - start.y))
                )
                draftFrame = CGRect(origin: origin, size: size)
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

    private func clamped(_ point: CGPoint, in canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(BoardViewModel.canvasSidePadding, point.x), canvasSize.width - BoardViewModel.canvasSidePadding),
            y: min(max(BoardViewModel.topCreationLimit, point.y), canvasSize.height - BoardViewModel.canvasSidePadding)
        )
    }
    
    private func startWorkspaceRename() {
        workspaceNameDraft = viewModel.activeWorkspace?.name ?? "Space \(viewModel.activeSlot)"
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
