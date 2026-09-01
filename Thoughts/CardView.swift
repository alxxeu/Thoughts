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
            
            MacRichTextEditor(text: $card.text, isFocused: _isTextFocused.projectedValue)
                           .frame(maxWidth: .infinity, maxHeight: .infinity)
                           .padding(20)
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
                           .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FocusNewCard"))) { notification in
                               if let targetID = notification.object as? UUID, targetID == card.id {
                                   isTextFocused = true
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
                        // Железно выставляем фокус текстового поля на Mac
                        isTextFocused = true
                    }
                }
            
            // КАСТОМНЫЙ ИНТУИТИВНЫЙ УГОЛОК ИЗМЕНЕНИЯ РАЗМЕРА (RESIZE HANDLE)
            Path { path in
                // 1. Начинаем сверху на правой грани (X: 14, Y: 0)
                               path.move(to: CGPoint(x: 8, y: 0))
                               
                               // 2. Ведем ровную вертикальную линию вниз почти до самого угла
                               path.addLine(to: CGPoint(x: 8, y: 0))
                               
                               // 3. Закругляем сам угол к нижней грани с радиусом 6 поинтов
                               path.addQuadCurve(
                                   to: CGPoint(x: 0, y: 8),
                                   control: CGPoint(x: 8, y: 8) // Точка жесткого угла
                               )
                               
                               // 4. Дорисовываем ровный горизонтальный хвостик влево (до X: 0, Y: 14)
                               path.addLine(to: CGPoint(x: 0, y: 8))
                           }
                           .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                           .frame(width: 8, height: 8) // Жестко задаем размер квадрата 14х14
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
            .padding(8) // Немного подогнали отступ, чтобы уголок идеально сел в скругление карточки
            .opacity(isHovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .zIndex(102)
            
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
            
            // КРЕСТИК УДАЛЕНИЯ С ЖЕЛЕЗНЫМ ТАЙМЕРОМ:
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
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(isPressingDelete ? .red : .white.opacity(0.3))
            }
            .contentShape(Circle())
            .padding(5)
            .opacity(isHovering ? 1 : 0) // Сам крестик появляется при ховере карточки
            .animation(.easeInOut(duration: 0.2), value: isHovering)
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
            .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 10, perform: {
                Task { @MainActor in
                    viewModel.deleteCard(card)
                    NSCursor.arrow.set()
                    resetDeleteState()
                }
            }, onPressingChanged: { pressing in
                if pressing {
                    isPressingDelete = true
                    withAnimation(.linear(duration: 0.4)) {
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
        // Принудительно отменяем текущую запущенную линейную анимацию,
        // чтобы круг мгновенно перестал заполняться дальше
        withAnimation(.none) {
            deleteProgress = 0.0
        }
        // Плавно возвращаем подложку в исходное прозрачное состояние
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
                            
                            // При отпускании мыши карточка должна плавно притянуться к финальному snap-эффекту бордеров
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

// Нативная обертка для NSTextView, которая открывает полноценный Rich Text на Mac
struct MacRichTextEditor: NSViewRepresentable {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        
        let textView = NSTextView()
        textView.autoresizingMask = [.width, .height]
        textView.isSelectable = true
        textView.isEditable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 15)
        
        // ВКЛЮЧАЕМ РИЧ-ТЕКСТ И СИСТЕМНЫЕ ХОТКЕИ (Cmd+B / Cmd+I)
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        if textView.string != text {
            textView.string = text
        }
        
        // Управляем фокусом ввода из SwiftUI на Mac
        DispatchQueue.main.async {
            if isFocused && nsView.window?.firstResponder != textView {
                nsView.window?.makeFirstResponder(textView)
            } else if !isFocused && nsView.window?.firstResponder == textView {
                if nsView.window?.firstResponder == textView {
                    nsView.window?.makeFirstResponder(nil)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacRichTextEditor

        init(_ parent: MacRichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
        }
        
        func textDidBeginEditing(_ notification: Notification) {
            if !self.parent.isFocused {
                self.parent.isFocused = true
            }
        }
        
        func textDidEndEditing(_ notification: Notification) {
            if self.parent.isFocused {
                self.parent.isFocused = false
            }
        }
    }
}
