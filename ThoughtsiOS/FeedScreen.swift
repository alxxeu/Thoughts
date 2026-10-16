import SwiftUI

/// Лента Space (S1): свежие карточки внизу у поля ввода, Spaces — полоса под полем,
/// свайп по ленте переключает Space, «…» → Settings. Тап по карточке — редактор (S2).
struct FeedScreen: View {
    @Bindable var board: BoardModel
    @State private var slot = 1
    @State private var draft = ""
    @State private var editing: EditorTarget?
    @State private var showSettings = false
    @State private var spacesCollapsed = false
    @State private var lock = LockSession()
    @State private var revealed = Set<UUID>()
    @State private var renaming: Workspace?
    @State private var newName = ""
    @FocusState private var composerFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    @State private var bottomBarHeight: CGFloat = 110
    /// Верх нижних баров в глобальных координатах: клавиатура сжимает GeometryReader,
    /// а лента под ней — нет, так что отступ ленты снизу считается от поля ввода.
    @State private var barTop: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
        // Страницы Spaces — горизонтальная прокрутка без обрезки (страничный TabView
        // обрезал ленту). Настоящие бары лежат поверх и не уезжают при свайпе; ленте
        // даны прозрачные бары той же высоты (отступы), а у краёв — свои затухания с
        // размытием, чуть темнее фона.
        let insets = EdgeInsets(top: geo.safeAreaInsets.top + 56, leading: 0,
                                bottom: 0, trailing: 0)
        ZStack {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(board.workspaces) { workspace in
                    FeedList(board: board, slot: workspace.slot, revealed: revealed, insets: insets, barTop: barTop,
                             onOpen: { editing = EditorTarget(card: $0, detent: .medium) },
                             onReveal: reveal,
                             onCollapse: { collapsed in if collapsed != spacesCollapsed { withAnimation(.snappy) { spacesCollapsed = collapsed } } })
                        .containerRelativeFrame(.horizontal)
                        .id(workspace.slot)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: Binding(get: { Optional(slot) }, set: { if let s = $0 { slot = s } }))
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .ignoresSafeArea()
        EdgeFade(edge: .top, height: geo.safeAreaInsets.top + 64)
        // Снизу — выше баров: захватывает папки и часть поля ввода.
        EdgeFade(edge: .bottom, height: geo.safeAreaInsets.bottom + bottomBarHeight * 0.8 + 30)
        }
        }
        // Бары — поверх, в безопасной зоне (клавиатура поднимает поле ввода сама).
        .overlay(alignment: .top) { HStack { Spacer(); moreButton }.padding(.top, 6) }
        .overlay(alignment: .bottom) {
            bottomBar.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                barTop = $0.minY; bottomBarHeight = $0.height
            }
        }
        .background(Theme.background.ignoresSafeArea())
        // Клавиатура закрывается свайпом по ленте (scrollDismissesKeyboard).
        .sheet(item: $editing) { target in
            EditorSheet(board: board, card: target.card, detent: target.detent, lock: lock)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("Rename Space", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename() }
        }
        .onChange(of: slot) { revealed = [] }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { lock.isUnlocked = false; revealed = [] }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Низ: поле ввода + Spaces

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // К старым карточкам поле чуть сжимается: на 30 pt с боков и на 6 pt сверху.
            let compact = spacesCollapsed && !composerFocused
            Composer(text: $draft, focused: $composerFocused, compact: compact, onSend: send, onExpand: expand)
                .padding(.horizontal, compact ? 46 : 16)
            if !composerFocused {
                // Полоса Spaces — во всю ширину, края уходят за экран с мягким затуханием.
                SpacesBar(workspaces: board.workspaces, slot: $slot, collapsed: spacesCollapsed,
                          onExpand: { withAnimation(.snappy) { spacesCollapsed = false } },
                          onRename: { renaming = $0; newName = $0.name })
            }
        }
        .padding(.bottom, 4)
        .animation(.snappy, value: composerFocused)
        .animation(.snappy, value: spacesCollapsed)
    }

    private var moreButton: some View {
        Menu {
            Button("Settings", systemImage: "gearshape") { showSettings = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)
        }
        .padding(.trailing, 16)
    }

    // MARK: - Действия

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        board.addCard(text: text, slot: slot)
        draft = ""
    }

    /// Расширитель поля (4+ строк): карточка с набранным текстом — сразу в редактор на весь экран (Р17).
    private func expand() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let card = board.addCard(text: text, slot: slot)
        draft = ""
        composerFocused = false
        editing = EditorTarget(card: card, detent: .large)
    }

    private func reveal(_ card: Card) {
        if card.privacyMode == .spoiler { withAnimation { _ = revealed.insert(card.id) } ; return }
        Task {
            if await lock.unlock() { withAnimation { _ = revealed.insert(card.id) } }
        }
    }

    private func rename() {
        guard let ws = renaming, let i = board.workspaces.firstIndex(where: { $0.slot == ws.slot }) else { return }
        let trimmed = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        board.workspaces[i].name = trimmed.isEmpty ? Workspace.defaultName(forSlot: ws.slot) : trimmed
        board.saveImmediately()
        renaming = nil
    }
}

private struct ScrollState: Equatable {
    var offset: CGFloat
    var toBottom: CGFloat
    var height: CGFloat
}

/// Мягкое затухание с размытием у края экрана, чуть темнее фона.
private struct EdgeFade: View {
    let edge: VerticalEdge
    let height: CGFloat

    var body: some View {
        let toEdge: (UnitPoint, UnitPoint) = edge == .top ? (.bottom, .top) : (.top, .bottom)
        ZStack {
            // Снизу размытие сильнее (доводка 3).
            Rectangle().fill(edge == .top ? .ultraThinMaterial : .thinMaterial)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: toEdge.0, endPoint: toEdge.1))
            LinearGradient(colors: [Theme.fade.opacity(0), Theme.fade.opacity(0.92)], startPoint: toEdge.0, endPoint: toEdge.1)
        }
        .frame(height: height)
        .frame(maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct EditorTarget: Identifiable {
    let card: Card
    let detent: PresentationDetent
    var id: UUID { card.id }
}

// MARK: - Лента одного Space

private struct FeedList: View {
    @Bindable var board: BoardModel
    let slot: Int
    let revealed: Set<UUID>
    /// Высота верхних баров (статус-бар + «…»); снизу отступ — до верха поля ввода.
    let insets: EdgeInsets
    let barTop: CGFloat
    var onOpen: (Card) -> Void
    var onReveal: (Card) -> Void
    var onCollapse: (Bool) -> Void

    /// Порядок замораживается: лента не перестраивается под пальцем — новый
    /// порядок при открытии Space и при возврате из редактора.
    @State private var order: [UUID] = []
    @State private var isDragging = false
    @State private var atBottom = true
    @State private var listBottom: CGFloat = 0

    private var cards: [Card] { board.cardsByWorkspace[slot] ?? [] }

    /// Без даты — в порядке холста Mac (сверху вниз, слева направо), затем по
    /// последней правке текста; свежие — внизу.
    private static func sorted(_ cards: [Card]) -> [Card] {
        cards.sorted { a, b in
            let au = a.contentModifiedAt == Card.unknownDate, bu = b.contentModifiedAt == Card.unknownDate
            if au != bu { return au }
            if au { return (a.position.y, a.position.x) < (b.position.y, b.position.x) }
            return a.contentModifiedAt < b.contentModifiedAt
        }
    }

    private var ordered: [Card] {
        let byID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let known = order.compactMap { byID[$0] }
        let fresh = Self.sorted(cards.filter { !order.contains($0.id) })
        return known + fresh
    }

    private var isProtected: Bool { board.workspaces.first { $0.slot == slot }?.isProtected ?? false }

    var body: some View {
        // Space Lock на iPhone ещё нет — защищённый Space закрыт целиком (fail-closed).
        if isProtected {
            VStack(spacing: 12) {
                Image(systemName: "lock.fill").font(.system(size: 28))
                Text("This Space is locked").font(.system(size: 15, weight: .semibold))
                Text("Space Lock on iPhone is coming soon.").font(.system(size: 13))
            }
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            list
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
        List {
            if cards.isEmpty {
                Text("Here’s nothing.\nTry to create your first Card")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(ordered) { card in
                CardRow(card: card, isRevealed: revealed.contains(card.id),
                        onReveal: { onReveal(card) },
                        onToggleTask: { toggle(card, $0) })
                    .onTapGesture { if card.privacyMode == .none || revealed.contains(card.id) { onOpen(card) } }
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = card.text }
                        ShareLink(item: card.text) { Label("Share", systemImage: "square.and.arrow.up") }
                        Button("Delete", systemImage: "trash", role: .destructive) { board.deleteCard(id: card.id) }
                    }
                    .modifier(EdgeDeleteSwipe { withAnimation { board.deleteCard(id: card.id) } })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
        }
        .listStyle(.plain)
        .safeAreaBar(edge: .top, spacing: 0) { Color.clear.frame(height: insets.top) }
        .safeAreaBar(edge: .bottom, spacing: 0) { Color.clear.frame(height: max(listBottom - barTop + 5, 0)) } // +5: зазор до поля = зазору между карточками
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { listBottom = $0 }
        .scrollEdgeEffectHidden(true, for: .all) // затухания свои, темнее фона (EdgeFade)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .defaultScrollAnchor(.bottom)
        // Полоса Spaces: палец вверх (к свежим) — разворачивается, вниз (к старым) —
        // сворачивается в точки (Р12). Только от пальца: сдвиги от смены высоты баров не в счёт.
        .onScrollPhaseChange { _, phase in isDragging = phase == .interacting } // отскок у края — не палец
        .onScrollGeometryChange(for: ScrollState.self) { geo in
            ScrollState(offset: geo.contentOffset.y,
                        toBottom: geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height + geo.contentInsets.bottom,
                        height: geo.containerSize.height - geo.contentInsets.bottom)
        } action: { old, new in
            // Клавиатура или поле ввода сжали видимую часть — лента у низа поднимается вместе с ними.
            if new.height != old.height, atBottom { scrollToBottom(proxy, animated: false); return }
            if isDragging || old.toBottom >= 24 { atBottom = new.toBottom < 24 }
            guard isDragging else { return }
            let delta = new.offset - old.offset
            if delta > 4 { onCollapse(false) } else if delta < -4 { onCollapse(true) }
        }
        // shortcut: держится только низ ленты; из середины карточки под клавиатурой
        // не поднимаются — нужен сдвиг contentOffset, если попросят.
        .onAppear {
            order = Self.sorted(cards).map(\.id)
            // List не держит defaultScrollAnchor(.bottom) — прокручиваем к свежей сами.
            Task { @MainActor in scrollToBottom(proxy, animated: false) }
        }
        .onChange(of: board.editingCardID) { _, id in if id == nil { withAnimation { order = Self.sorted(cards).map(\.id) } } }
        .onChange(of: cards.count) { old, new in if new > old { scrollToBottom(proxy, animated: true) } }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = ordered.last?.id else { return }
        if animated { withAnimation(.snappy) { proxy.scrollTo(last, anchor: .bottom) } } else { proxy.scrollTo(last, anchor: .bottom) }
    }

    private func toggle(_ card: Card, _ paragraph: MarkdownStyler.Paragraph) {
        guard let text = MarkdownFormatting.togglingTask(in: card.text, paragraph: paragraph) else { return }
        card.text = text
        board.saveImmediately()
    }
}

// MARK: - Поле ввода

private struct Composer: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var compact = false
    var onSend: () -> Void
    var onExpand: () -> Void
    @State private var height: CGFloat = 0

    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// 4+ строк — появляется расширитель (Р17).
    private var isLong: Bool { height > 70 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Type a thought…", text: $text, axis: .vertical)
                .lineLimit(1...9) // ≈ 200 pt, дальше — прокрутка внутри
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .focused(focused)
                .padding(.vertical, 6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            if hasText {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Theme.accent, in: .circle)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        // Расширитель — над кнопкой отправки, в оверлее: Spacer в стопке тянул поле до верха экрана.
        .overlay(alignment: .topTrailing) {
            if hasText && isLong {
                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 32, height: 32)
                }
                .transition(.opacity)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, hasText ? 8 : 18)
        .padding(.vertical, compact ? 5 : 8) // поровну сверху и снизу — подпись остаётся по центру
        .frame(minHeight: compact ? 42 : 48)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .animation(.snappy, value: hasText)
        .animation(.snappy, value: isLong)
    }
}

// MARK: - Полоса Spaces

private struct SpacesBar: View {
    let workspaces: [Workspace]
    @Binding var slot: Int
    let collapsed: Bool
    var onExpand: () -> Void
    var onRename: (Workspace) -> Void

    @State private var centered: Int?
    @State private var widths: [Int: CGFloat] = [:]
    @State private var barWidth: CGFloat = 400

    @Namespace private var morph

    var body: some View {
        Group {
            if collapsed { dots } else { names }
        }
        // centered живёт и при свёрнутой полосе — раскрытая встаёт сразу на нужное имя.
        .onAppear { centered = slot }
        .onChange(of: centered) { _, c in
            if let c, c != slot { withAnimation(.snappy) { slot = c } }
        }
        .onChange(of: slot) { _, s in
            if centered != s { withAnimation(.snappy) { centered = s } }
        }
    }

    /// Свёрнуто: ряд точек; точка текущего Space — та же капсула, что под именем.
    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(workspaces) { ws in
                if ws.slot == slot {
                    Capsule().fill(Theme.text)
                        .matchedGeometryEffect(id: "current", in: morph)
                        .frame(width: 16, height: 6)
                } else {
                    Capsule().fill(Theme.secondary).frame(width: 6, height: 6)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .contentShape(.rect)
        .onTapGesture(perform: onExpand) // тап по точкам — раскрыть
        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
    }

    /// Раскрыто: имена всплывают снизу из точек, капсула вырастает из точки текущего.
    private var names: some View {
        // Капсула стоит на месте, имена едут под ней; имя в центре — текущий Space.
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(workspaces) { ws in
                        Text(ws.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ws.slot == centered ? Theme.text : Theme.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widths[ws.slot] = $0 }
                            .contentShape(.capsule)
                            .onTapGesture { withAnimation(.snappy) { centered = ws.slot } }
                            .contextMenu { Button("Rename…", systemImage: "pencil") { onRename(ws) } }
                            .id(ws.slot)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $centered, anchor: .center)
            // viewAligned прижимает имя левым краем — доводим до центра сами, когда лента встала.
            .onScrollPhaseChange { _, phase in
                if phase == .idle, let c = centered { withAnimation(.snappy) { proxy.scrollTo(c, anchor: .center) } }
            }
            // Поля в полширины, чтобы и крайние имена вставали в центр.
            .contentMargins(.horizontal, barWidth / 2, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
            .onAppear {
                // Встать на текущее имя без анимации — иначе лента прокатывается слева.
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { proxy.scrollTo(slot, anchor: .center) }
            }
        }
        .frame(height: 40)
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.88), .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        }
        .background {
            Capsule().fill(.clear)
                .glassEffect(.regular, in: .capsule)
                .matchedGeometryEffect(id: "current", in: morph)
                .frame(width: widths[centered ?? slot] ?? 80, height: 36)
                .animation(.snappy, value: centered)
        }
        .transition(.asymmetric(
            insertion: .offset(y: 14).combined(with: .scale(scale: 0.7, anchor: .bottom)).combined(with: .opacity),
            removal: .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity)))
    }
}

// MARK: - Удаление свайпом с правого края

/// Свайп удаления ловит только правый край карточки (56 pt); по остальной карточке
/// горизонтальный свайп листает Spaces. Повторяет системный: красный круг
/// тянется за карточкой в капсулу, за порогом полного свайпа (с отдачей) значок уходит
/// к краю карточки, отпустил — карточка уезжает и удаляется. Короткий свайп —
/// кнопка остаётся открытой.
private struct EdgeDeleteSwipe: ViewModifier {
    var onDelete: () -> Void
    @State private var offset: CGFloat = 0
    @State private var isOpen = false
    @State private var width: CGFloat = 0
    private let zone: CGFloat = 56
    private let revealed: CGFloat = 80
    private let gap: CGFloat = 8
    private var fullSwipe: CGFloat { max(width * 0.55, 160) }
    private var armed: Bool { -offset > fullSwipe }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .background(alignment: .trailing) {
                if offset < 0 {
                    // Круг 52 pt по центру высоты; дальше тянется за карточкой в капсулу.
                    let w = max(-offset - gap * 2, 0)
                    Button(action: delete) {
                        Image(systemName: "trash")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .scaleEffect(min(1, w / 52))
                            .frame(width: 52)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: armed ? .leading : .center)
                            .background(.red, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .frame(width: w, height: min(52, w))
                    .clipShape(.capsule)
                    .padding(.trailing, gap)
                    .animation(.snappy, value: armed)
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: armed) { _, new in new }
            .overlay(alignment: .trailing) {
                if isOpen {
                    // Открыто: тап по карточке — закрыть, кнопка справа — удалить, тянуть дальше — полный свайп.
                    Color.clear.contentShape(.rect)
                        .padding(.trailing, revealed)
                        .onTapGesture { close() }
                        .highPriorityGesture(drag)
                } else {
                    Color.clear.frame(width: zone).contentShape(.rect)
                        .highPriorityGesture(drag)
                }
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { offset = min(0, (isOpen ? -revealed : 0) + $0.translation.width) }
            .onEnded { _ in
                if armed { delete(); return }
                withAnimation(.snappy) {
                    isOpen = -offset > revealed / 2
                    offset = isOpen ? -revealed : 0
                }
            }
    }

    private func close() { withAnimation(.snappy) { isOpen = false; offset = 0 } }

    /// Карточка уезжает влево вместе с растянутой кнопкой, потом удаляется.
    private func delete() {
        withAnimation(.easeIn(duration: 0.2)) { offset = -width - gap * 4 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            onDelete()
        }
    }
}
