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
    
    @FocusState private var isTextFocused: Bool
    
    private var pad: CGFloat { BoardViewModel.canvasSidePadding }
    private var topLimit: CGFloat { BoardViewModel.topCreationLimit }
    
    var body: some View {
        ZStack(alignment: SwiftUI.Alignment.topLeading) {
            // ВЕРНУЛИ РОДНОЙ GLASS EFFECT:
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.clear)
                .glassEffect(in: .rect(cornerRadius: 16.0))
            
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
                }
                .onChange(of: isTextFocused) { _, isFocused in
                    if isFocused {
                        viewModel.bringToFront(card)
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
            
            // КАСТОМНЫЙ ИНТУИТИВНЫЙ УГОЛОК ИЗМЕНЕНИЯ РАЗМЕРА (RESIZE HANDLE)
            Path { path in
                // Математически смещаем штрих на 10 поинтов от правого нижнего края зоны 32x32:
                // Точка начала на правой грани (X: 22, Y: 14)
                path.move(to: CGPoint(x: 22, y: 14))
                path.addLine(to: CGPoint(x: 22, y: 14))
                
                // Закругляем к нижней грани (X: 14, Y: 22) с точкой притяжения в (22, 22)
                path.addQuadCurve(
                    to: CGPoint(x: 14, y: 22),
                    control: CGPoint(x: 22, y: 22)
                )
                path.addLine(to: CGPoint(x: 14, y: 22))
            }
            .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            
            // Задаем один монолитный фрейм 32x32 без внутренней вложенности и БЕЗ внешнего .padding
            .frame(width: 32, height: 32)
            .contentShape(Rectangle()) // Теперь вся зона 32х32 в самом углу карточки кликабельна
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
            // ПРИМЕЧАНИЕ: Внешний .padding(10) полностью удален, кнопка прижата к углам
            .opacity(isHovering ? 1 : 0)
            .zIndex(101)

            
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
            
            // КРЕСТИК УДАЛЕНИЯ С РАЗДЕЛЬНЫМ ХОВЕРОМ
            ZStack {
                // 1. Фоновая подложка теперь загорается ТОЛЬКО при наведении на сам крестик или при его зажатии
                Circle()
                    .fill(Color.white.opacity(isPressingDelete ? 0.15 : (isHoveringDeleteButton ? 0.08 : 0.0)))
                    .frame(width: 20, height: 20)
                    .animation(.easeIn(duration: 0.1), value: isHoveringDeleteButton)
                
                // 2. Индикатор прогресса удаления
                Circle()
                    .trim(from: 0.0, to: deleteProgress)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(-90))
                
                // 3. Сама иконка крестика (видна всегда, когда мышь над карточкой)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(isPressingDelete ? .red : .white.opacity(0.55))
            }
            .contentShape(Circle())
            .padding(5)
            .opacity(isHovering ? 1 : 0) // Сам крестик появляется при ховере карточки
            .zIndex(103)
            .onHover { inside in
                // Переключаем локальное состояние ховера кнопки
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
    }
    
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
}
