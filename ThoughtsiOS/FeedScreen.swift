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
    @State private var showSpaceSettings = false
    /// Карточка, удаление которой ждёт подтверждения (меню, кнопка-корзина). Полный свайп — без него.
    @State private var pendingDelete: Card?
    /// Порядок страниц на время дальнего перехода по полосе: нужный Space ставится
    /// рядом с текущим, лента прокручивается на одну страницу, потом порядок обратно.
    @State private var pageOrder: [Int]?
    @State private var realign = 0
    @AppStorage("hideEmptySpaces") private var hideEmptySpaces = false
    /// Видимые Spaces с «Hide empty Spaces» — пересчитываются не при смене Space:
    /// иначе пустой Space пропадал из страниц прямо во время прокрутки с него, и
    /// лента перескакивала.
    @State private var visibleSlots: [Int]?
    @FocusState private var composerFocused: Bool
    /// Фокус поля — тем же значением, но с анимацией: фокус приходит из UIKit без неё,
    /// и полоса Spaces исчезала за кадр — лента дёргалась до подъёма клавиатуры.
    @State private var typing = false
    @Environment(\.scenePhase) private var scenePhase

    /// Растёт, когда начинают листать Spaces, — открытые кнопки удаления закрываются.
    @State private var swipeReset = 0

    var body: some View {
        GeometryReader { geo in
        // Страницы Spaces — горизонтальная прокрутка без обрезки (страничный TabView
        // обрезал ленту). Настоящие бары лежат поверх и не уезжают при свайпе; ленте
        // даны прозрачные бары той же высоты (отступы), а у краёв — свои затухания с
        // размытием, чуть темнее фона.
        let insets = EdgeInsets(top: geo.safeAreaInsets.top + 56, leading: 0,
                                bottom: 0, trailing: 0)
        ZStack {
        ScrollViewReader { pager in
        ScrollView(.horizontal) {
            // Не Lazy: страницы всех Spaces собраны заранее. Иначе при дальнем переходе
            // нужная страница строилась (ленту, Markdown) прямо посреди прокрутки — фриз,
            // тем заметнее, чем больше в Space карточек. Строки внутри List и так ленивые.
            // Собраны страницы текущего Space и соседних: на смену высоты (клавиатура, панели)
            // перекладывается каждая живая страница, и девять лент разом давали лаги. Остальные — пустые места.
            let currentPage = pages.firstIndex { $0.slot == slot } ?? 0
            HStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, workspace in
                    if abs(index - currentPage) > 1 {
                        Color.clear.containerRelativeFrame(.horizontal).id(workspace.slot)
                    } else {
                    FeedList(board: board, slot: workspace.slot, isCurrent: workspace.slot == slot, revealed: revealed, insets: insets,
                             onOpen: { editing = EditorTarget(card: $0, detent: .medium) },
                             onReveal: reveal,
                             onAskDelete: { pendingDelete = $0 },
                             onPrivacy: setPrivacy,
                             onCollapse: { collapsed in if collapsed != spacesCollapsed { withAnimation(.snappy) { spacesCollapsed = collapsed } } })
                        .containerRelativeFrame(.horizontal)
                        .id(workspace.slot)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .onScrollPhaseChange { _, phase in if phase == .interacting { swipeReset += 1 } }
        .environment(\.swipeReset, swipeReset)
        .scrollPosition(id: Binding(get: { Optional(slot) }, set: { if let s = $0 { slot = s } }))
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        // Сверху лента уходит под статус-бар (свои отступ и затухание); снизу — системная
        // вставка с полем ввода: клавиатуру и рост панели iOS отрабатывает сама, в одной анимации.
        .ignoresSafeArea(.container, edges: .top)
        // Порядок страниц вернули после дальнего перехода — лента держит место по
        // номеру страницы, а не по Space; ставим её обратно на текущий Space.
        .onChange(of: realign) { pager.scrollTo(slot) }
        }
        EdgeFade(edge: .top, height: geo.safeAreaInsets.top + 64)
        }
        }
        .overlay(alignment: .top) { HStack { Spacer(); moreButton }.padding(.top, 6) }
        // Поле ввода и Spaces — системная вставка снизу: лента прокручивается под ней,
        // клавиатура поднимает её вместе с лентой без ручных замеров.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Нижнее затухание — фон самой панели: выше неё на 40 pt и до низа экрана.
            // Двигается вместе с панелью в той же анимации клавиатуры (раньше высота
            // считалась из GeometryReader и прыгала при скрытии клавиатуры).
            bottomBar.background(alignment: .bottom) {
                BottomFade().padding(.top, -40).ignoresSafeArea(edges: .bottom)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        // Клавиатура закрывается свайпом по ленте (scrollDismissesKeyboard).
        .sheet(item: $editing) { target in
            EditorSheet(board: board, card: target.card, detent: target.detent)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showSpaceSettings) { SpaceSettingsView(board: board) }
        .alert("Rename Space", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
                .onChange(of: newName) { if newName.count > Workspace.maxNameLength { newName = String(newName.prefix(Workspace.maxNameLength)) } }
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename() }
        }
        .alert("Delete card?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let card = pendingDelete { withAnimation { board.deleteCard(id: card.id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone.")
        }
        .onChange(of: slot) { revealed = [] }
        .onAppear(perform: refreshVisibleSlots)
        .onChange(of: hideEmptySpaces) { refreshVisibleSlots() }
        .onChange(of: nonEmptySlots) { refreshVisibleSlots() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { lock.isUnlocked = false; revealed = [] }
            if phase == .active { refreshVisibleSlots() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Низ: поле ввода + Spaces

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // К старым карточкам поле чуть сжимается: на 30 pt с боков и на 6 pt сверху.
            let compact = spacesCollapsed && !typing
            Composer(text: $draft, focused: $composerFocused, compact: compact, onSend: send, onExpand: expand)
                .padding(.horizontal, compact ? 46 : 16)
                // Сжатое поле на 6 pt ниже — добираем сверху: высота панели не меняется,
                // и лента под ней не сдвигается (иначе сдвиг читался как свайп — петля).
                .padding(.top, compact ? 6 : 0)
            if !typing {
                // Полоса Spaces — во всю ширину, края уходят за экран с мягким затуханием.
                SpacesBar(workspaces: visibleWorkspaces, slot: $slot, collapsed: spacesCollapsed,
                          onExpand: { withAnimation(.snappy) { spacesCollapsed = false } },
                          onRename: { renaming = $0; newName = $0.name },
                          onSettings: { showSpaceSettings = true },
                          onSelect: select)
            }
        }
        .padding(.bottom, 4)
        .animation(.snappy, value: spacesCollapsed)
        .onChange(of: composerFocused) { _, focused in withAnimation(.snappy) { typing = focused } }
    }

    private var moreButton: some View {
        Menu {
            Button("Spaces", systemImage: "square.stack") { showSpaceSettings = true }
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

    /// Spaces в полосе и ленте; с «Hide empty Spaces» — без пустых, кроме текущего.
    private var visibleWorkspaces: [Workspace] {
        guard hideEmptySpaces, let visibleSlots else { return board.workspaces }
        return board.workspaces.filter { visibleSlots.contains($0.slot) }
    }

    private var nonEmptySlots: Set<Int> { Set(board.cardsByWorkspace.filter { !$0.value.isEmpty }.keys) }

    /// Непустые Spaces и текущий; Space, с которого ушли, остаётся до следующего пересчёта.
    private func refreshVisibleSlots() {
        visibleSlots = board.workspaces.map(\.slot).filter { nonEmptySlots.contains($0) || $0 == slot }
    }

    // MARK: - Действия

    /// Страницы ленты: обычный порядок или временный — на время дальнего перехода.
    private var pages: [Workspace] {
        guard let pageOrder else { return visibleWorkspaces }
        return pageOrder.compactMap { slot in visibleWorkspaces.first { $0.slot == slot } }
    }

    /// Тап по имени в полосе. Дальний Space на время перехода встаёт рядом с текущим
    /// (с той стороны, где он в полосе), и лента прокручивается на одну страницу, как к
    /// соседу. Текущая страница при перестановке не сдвигается: до неё столько же страниц.
    private func select(_ target: Int) {
        var ids = visibleWorkspaces.map(\.slot)
        guard let from = ids.firstIndex(of: slot), let to = ids.firstIndex(of: target), from != to else { return }
        if abs(to - from) == 1 { withAnimation(.snappy) { slot = target }; return }
        ids.remove(at: to)
        let current = ids.firstIndex(of: slot) ?? from
        ids.insert(target, at: to > from ? current + 1 : current)
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { pageOrder = ids }
        Task { @MainActor in
            withAnimation(.snappy) { slot = target } completion: {
                withTransaction(still) { pageOrder = nil; realign += 1 }
            }
        }
    }

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

    /// Spoiler / Lock со свайпа: карточка сразу прячется (раскрытие сбрасывается).
    private func setPrivacy(_ card: Card, _ mode: CardPrivacyMode) {
        withAnimation(.snappy) {
            card.privacyMode = mode
            revealed.remove(card.id)
        }
        board.saveImmediately()
    }

    private func reveal(_ card: Card) {
        if card.privacyMode == .spoiler { withAnimation { _ = revealed.insert(card.id) } ; return }
        Task {
            if await lock.unlock() { withAnimation { _ = revealed.insert(card.id) } }
        }
    }

    private func rename() {
        if let ws = renaming { board.renameWorkspace(slot: ws.slot, to: newName) }
        renaming = nil
    }
}

/// Затухание с размытием под нижней панелью, чуть темнее фона; растягивается по
/// панели, сверху прозрачное.
private struct BottomFade: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.thinMaterial)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
            LinearGradient(colors: [Theme.fade.opacity(0), Theme.fade.opacity(0.92)], startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
    }
}

/// Мягкое затухание с размытием у верхнего края экрана, чуть темнее фона.
private struct EdgeFade: View {
    let edge: VerticalEdge
    let height: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .bottom, endPoint: .top))
            LinearGradient(colors: [Theme.fade.opacity(0), Theme.fade.opacity(0.92)], startPoint: .bottom, endPoint: .top)
        }
        .frame(height: height)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct ScrollSpot: Equatable {
    var offset: CGFloat
    var inBounds: Bool
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
    let isCurrent: Bool
    let revealed: Set<UUID>
    /// Высота верхних баров (статус-бар + «…»); снизу отступ — до верха поля ввода.
    let insets: EdgeInsets
    var onOpen: (Card) -> Void
    var onReveal: (Card) -> Void
    var onAskDelete: (Card) -> Void
    var onPrivacy: (Card, CardPrivacyMode) -> Void
    var onCollapse: (Bool) -> Void

    /// Порядок замораживается: лента не перестраивается под пальцем — новый
    /// порядок при открытии Space и при возврате из редактора.
    @State private var order: [UUID] = []
    @State private var isDragging = false
    /// Путь пальца в одну сторону — полоса Spaces меняется после порога, а не на каждый пиксель.
    @State private var travel: CGFloat = 0
    @State private var listReset = 0
    /// Лента «как в чате»: стоит на свежих внизу. Начальное положение, полупустой
    /// Space у поля и подъём вместе с клавиатурой — всё делает defaultScrollAnchor(.bottom).
    @State private var position = ScrollPosition(edge: .bottom)


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

    @State private var stars = StarVoidModel()

    /// Пустой Space: картинка как эмодзи над подписью, всё по центру экрана.
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image("Tumbleweed").resizable().scaledToFit().frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Here’s nothing.\nTry to create your first Card")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(ordered) { card in
                    let isHidden = card.privacyMode != .none && !revealed.contains(card.id)
                    CardRow(card: card, isRevealed: revealed.contains(card.id),
                            onReveal: { onReveal(card) },
                            onToggleTask: { toggle(card, $0) },
                            onOpen: { if !isHidden { onOpen(card) } },
                            isOffPage: !isCurrent, stars: stars)
                        .onTapGesture { if !isHidden { onOpen(card) } }
                        .modifier(CardMenu(card: card, isHidden: isHidden, onDelete: { onAskDelete(card) }))
                        // Нераскрытую карточку нельзя ни удалить, ни сменить ей защиту свайпом.
                        .modifier(CardSwipe(isEnabled: !isHidden, privacy: card.privacyMode,
                                            onDelete: { withAnimation { board.deleteCard(id: card.id) } },
                                            onAskDelete: { onAskDelete(card) },
                                            onPrivacy: { onPrivacy(card, $0) },
                                            onTap: { onOpen(card) }))
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 5)
            .padding(.bottom, 10) // зазор до поля = зазору между карточками
        }
        .scrollPosition($position)
        .overlay { StarEmitter(model: stars, isPaused: !isCurrent).allowsHitTesting(false) }
        .overlay { if cards.isEmpty { emptyState } }
        .defaultScrollAnchor(.bottom)
        .safeAreaBar(edge: .top, spacing: 0) { Color.clear.frame(height: insets.top) }
        .scrollEdgeEffectHidden(true, for: .all) // затухания свои, темнее фона (EdgeFade)
        .scrollDismissesKeyboard(.interactively)
        // Полоса Spaces: палец вверх (к свежим) — разворачивается, вниз (к старым) —
        // сворачивается в точки (Р12). Только от пальца: сдвиги от смены высоты баров не в счёт.
        .onScrollPhaseChange { _, phase in
            isDragging = phase == .interacting // отскок у края — не палец
            if phase == .interacting { travel = 0 }
            if phase == .interacting { listReset += 1 } // прокрутка ленты закрывает кнопки удаления
        }
        .transformEnvironment(\.swipeReset) { $0 += listReset }
        .onScrollGeometryChange(for: ScrollSpot.self) { geo in
            let top = -geo.contentInsets.top
            let bottom = max(top, geo.contentSize.height - geo.containerSize.height + geo.contentInsets.bottom)
            return ScrollSpot(offset: geo.contentOffset.y, inBounds: geo.contentOffset.y >= top && geo.contentOffset.y <= bottom)
        } action: { old, new in
            // Оверсвайп (пружина у края) и сдвиги не от пальца — не в счёт.
            guard isDragging, old.inBounds, new.inBounds else { return }
            let delta = new.offset - old.offset
            if delta == 0 { return }
            if (delta > 0) != (travel > 0) { travel = 0 } // сменилось направление — считаем заново
            travel += delta
            if travel > 24 { onCollapse(false) } else if travel < -24 { onCollapse(true) }
        }
        .onAppear { order = Self.sorted(cards).map(\.id) }
        .onChange(of: board.editingCardID) { _, id in if id == nil { withAnimation { order = Self.sorted(cards).map(\.id) } } }
        .onChange(of: cards.count) { old, new in if new > old { withAnimation(.snappy) { position.scrollTo(edge: .bottom) } } }
    }

    private func toggle(_ card: Card, _ edit: MarkdownFormatting.Edit) {
        card.text = (card.text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
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
    var onSettings: () -> Void
    var onSelect: (Int) -> Void

    @State private var barWidth: CGFloat = 400

    var body: some View {
        if collapsed { dots } else { names }
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(workspaces) { ws in
                Capsule()
                    .fill(ws.slot == slot ? Theme.text : Theme.secondary)
                    .frame(width: ws.slot == slot ? 16 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40) // как у имён: свёрнутая полоса не меняет высоту панели
        .contentShape(.rect)
        .onTapGesture(perform: onExpand) // тап по точкам — раскрыть
        .transition(.opacity)
    }

    /// Простая прокрутка имён; Space меняется только тапом по имени. Текущий —
    /// ярче и чуть крупнее, лента держит его по центру.
    private var names: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(workspaces) { ws in
                        let isCurrent = ws.slot == slot
                        Text(ws.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isCurrent ? Theme.text : Theme.secondary)
                            .scaleEffect(isCurrent ? 1.12 : 1)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .contentShape(.rect)
                            .onTapGesture { onSelect(ws.slot) }
                            .contextMenu {
                                Button("Rename…", systemImage: "pencil") { onRename(ws) }
                                Button("Space Settings…", systemImage: "slider.horizontal.3", action: onSettings)
                            }
                            .id(ws.slot)
                    }
                }
            }
            // Поля, чтобы и крайние имена могли встать по центру.
            .contentMargins(.horizontal, max(barWidth / 2 - 40, 0), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
            .onAppear {
                // Раскрылась из точек — сразу на текущем имени, без прокатывания.
                proxy.scrollTo(slot, anchor: .center)
                Task { @MainActor in proxy.scrollTo(slot, anchor: .center) }
            }
            .onChange(of: slot) { _, s in withAnimation(.snappy) { proxy.scrollTo(s, anchor: .center) } }
            .onChange(of: workspaces.map(\.name)) { proxy.scrollTo(slot, anchor: .center) }
        }
        .frame(height: 40)
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.88), .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        }
        .transition(.opacity)
    }
}

// MARK: - Меню долгого нажатия

/// Copy / Share / Delete по долгому нажатию. Нераскрытая Spoiler/Lock-карточка меню
/// не даёт вовсе (Copy отдал бы текст без Face ID): только отклик и короткое всплывание.
private struct CardMenu: ViewModifier {
    let card: Card
    let isHidden: Bool
    var onDelete: () -> Void
    @State private var pulse = false

    func body(content: Content) -> some View {
        if isHidden {
            content
                .scaleEffect(pulse ? 1.03 : 1)
                .sensoryFeedback(.impact(weight: .light), trigger: pulse) { _, new in new }
                .onLongPressGesture(minimumDuration: 0.35) {
                    withAnimation(.spring(duration: 0.18)) { pulse = true } completion: {
                        withAnimation(.spring(duration: 0.35, bounce: 0.5)) { pulse = false }
                    }
                }
        } else {
            content
                .contentShape(.contextMenuPreview, .rect(cornerRadius: Theme.cardRadius)) // превью без прямоугольной рамки
                .contextMenu { CardActions(card: card, onDelete: onDelete) }
        }
    }
}

// MARK: - Свайпы по краям карточки

/// Свайпы ловят только края карточки (справа 56 pt, слева 20 pt); по остальной карточке горизонтальный
/// свайп листает Spaces. Повторяют системные: круги тянутся за карточкой в капсулу,
/// за порогом полного свайпа — отклик, значок уходит к карточке, отпустил — действие.
/// Короткий свайп оставляет кнопки открытыми.
/// - справа ← удаление: кнопка-корзина спрашивает подтверждение, полный свайп удаляет сразу;
/// - слева → Spoiler и Lock: кнопки переключают режим, полный свайп включает Lock,
///   а на уже защищённой карточке снимает защиту.
private struct CardSwipe: ViewModifier {
    let isEnabled: Bool
    let privacy: CardPrivacyMode
    var onDelete: () -> Void
    var onAskDelete: () -> Void
    var onPrivacy: (CardPrivacyMode) -> Void
    /// Тап по краю карточки: зоны свайпа лежат поверх и иначе глотали бы его.
    var onTap: () -> Void

    /// < 0 — карточка уехала влево (удаление), > 0 — вправо (Spoiler / Lock).
    @State private var offset: CGFloat = 0
    @State private var openOffset: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var height: CGFloat = 0
    /// Значок у края капсулы — отдельным состоянием с явной анимацией: неявная
    /// тонула в непрерывных обновлениях свайпа.
    @State private var iconAtEdge = false
    @Environment(\.swipeReset) private var swipeReset
    /// Правый край — 56 pt (удаление); левый — 20 pt: дальше уже квадратики задач.
    private let zone: CGFloat = 56
    private let leadingZone: CGFloat = 20
    private let button: CGFloat = 52
    private let gap: CGFloat = 8
    private var deleteRevealed: CGFloat { button + gap * 2 }
    private var privacyRevealed: CGFloat { button * 2 + gap * 3 }
    private var fullSwipe: CGFloat { max(width * 0.55, 160) }
    private var armed: Bool { abs(offset) > fullSwipe }

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .offset(x: offset)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { width = $0.width; height = $0.height }
                .background(alignment: .trailing) { if offset < 0 { deleteButton } }
                .background(alignment: .leading) { if offset > 0 { privacyButtons } }
                .sensoryFeedback(.impact(weight: .medium), trigger: armed) { _, new in new }
                .onChange(of: armed) { _, a in withAnimation(.spring(duration: 0.22, bounce: 0.35)) { iconAtEdge = a } }
                .onChange(of: swipeReset) { if offset != 0 { close() } }
                .overlay {
                    if openOffset != 0 {
                        // Открыто: тап по карточке — закрыть, тянуть дальше — полный свайп.
                        Color.clear.contentShape(.rect)
                            .padding(openOffset < 0 ? .trailing : .leading, abs(openOffset))
                            .onTapGesture { close() }
                            .highPriorityGesture(drag(openOffset < 0 ? -1 : 1))
                    } else {
                        HStack {
                            Color.clear.frame(width: leadingZone).contentShape(.rect)
                                .onTapGesture(perform: onTap).highPriorityGesture(drag(1))
                            Spacer()
                            Color.clear.frame(width: zone).contentShape(.rect)
                                .onTapGesture(perform: onTap).highPriorityGesture(drag(-1))
                        }
                    }
                }
        } else {
            content
        }
    }

    // MARK: Кнопки

    /// Подпись под кнопкой (как в Telegram) — если карточка достаточно высокая;
    /// на однострочной она залезла бы на соседнюю карточку.
    private var showsTitles: Bool { height >= 76 }

    private var deleteButton: some View {
        action("trash", title: "Delete", tint: .red, width: max(-offset - gap * 2, 0), shift: iconAtEdge ? -1 : 0) {
            close(); onAskDelete()
        }
        .padding(.trailing, gap)
    }

    /// Lock у края экрана — он и тянется в капсулу при полном свайпе; Spoiler — ближе к карточке.
    private var privacyButtons: some View {
        let w = max(offset - gap * 2, 0)
        let spoiler = iconAtEdge ? 0 : min(button, max(0, (w - gap) / 2))
        let lock = max(0, w - spoiler - (spoiler > 0 ? gap : 0))
        return HStack(spacing: spoiler > 0 ? gap : 0) {
            action(privacy == .lock ? "lock.open.fill" : "lock.fill", title: privacy == .lock ? "Unlock" : "Lock",
                   tint: Theme.accent, width: lock, shift: iconAtEdge ? 1 : 0) {
                close(); onPrivacy(privacy == .lock ? .none : .lock)
            }
            action(privacy == .spoiler ? "eye.fill" : "sparkles", title: privacy == .spoiler ? "Unblur" : "Spoiler",
                   tint: Color(white: 0.32), width: spoiler, shift: 0) {
                close(); onPrivacy(privacy == .spoiler ? .none : .spoiler)
            }
        }
        .padding(.leading, gap)
    }

    /// Круг 52 pt (44 с подписью) по центру высоты; дальше тянется за карточкой в капсулу.
    /// shift — куда уходит значок за порогом: −1 к левому краю капсулы, +1 к правому.
    private func action(_ symbol: String, title: String, tint: Color, width w: CGFloat, shift: CGFloat,
                        perform: @escaping () -> Void) -> some View {
        let side = showsTitles ? 44 : button
        return VStack(spacing: 5) {
            Button(action: perform) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .scaleEffect(min(1, w / side))
                    .modifier(IconShift(progress: shift, width: w))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Сплошной цвет + скругление слоя, а не Capsule: форма-путь при ширине,
                    // меняющейся каждый кадр, перерисовывалась в новую поверхность (лаги).
                    .background(tint)
            }
            .buttonStyle(.plain)
            .frame(width: w, height: min(side, w))
            .clipShape(.rect(cornerRadius: min(side, w) / 2))
            if showsTitles {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: w)
                    .opacity(min(1, w / side))
            }
        }
    }

    // MARK: Жест

    /// Как системный свайп (UIContextualAction): карточка идёт за пальцем, за краем —
    /// с сопротивлением; открыть/закрыть решает и путь, и скорость (бросок открывает);
    /// отпускание — пружиной, которая продолжает скорость пальца.
    /// side: −1 — правый край (удаление), +1 — левый (Spoiler / Lock).
    private func drag(_ side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let raw = side < 0 ? min(0, openOffset + value.translation.width) : max(0, openOffset + value.translation.width)
                offset = rubberBand(raw)
            }
            .onEnded { value in
                let velocity = value.velocity.width
                if armed {
                    if offset < 0 { deleteOut(velocity: velocity) } else { fullPrivacy(velocity: velocity) }
                    return
                }
                let revealed = offset < 0 ? deleteRevealed : privacyRevealed
                // Куда карточка доехала бы по инерции — как decelerationRate у UIScrollView.
                let projected = abs(openOffset + value.predictedEndTranslation.width)
                let open = projected > revealed / 2 && (openOffset + value.predictedEndTranslation.width) * side > 0
                let target = open ? (side < 0 ? -revealed : revealed) : 0
                settle(to: target, velocity: velocity)
            }
    }

    /// За шириной карточки — сопротивление, как у края UIScrollView.
    private func rubberBand(_ raw: CGFloat) -> CGFloat {
        let limit = max(width * 0.85, 1)
        let distance = abs(raw)
        guard distance > limit else { return raw }
        let over = distance - limit
        let damped = limit + over * 0.55 / (1 + over / limit)
        return raw < 0 ? -damped : damped
    }

    /// Пружина, стартующая со скоростью пальца (скорость — в долях пути, как у UIKit).
    private func settle(to target: CGFloat, velocity: CGFloat) {
        let distance = target - offset
        let relative = abs(distance) > 1 ? velocity / distance : 0
        withAnimation(.interpolatingSpring(mass: 1, stiffness: 280, damping: 30, initialVelocity: relative)) {
            openOffset = target
            offset = target
        }
    }

    private func close() { settle(to: 0, velocity: 0) }

    /// Карточка уезжает влево вместе с растянутой кнопкой — со скоростью пальца, потом удаляется.
    private func deleteOut(velocity: CGFloat = 0) {
        let target = -width - gap * 4
        let speed = max(abs(velocity), 900)
        let duration = min(0.25, max(0.12, Double(abs(target - offset) / speed)))
        withAnimation(.easeOut(duration: duration)) { offset = target }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            onDelete()
        }
    }

    /// Полный свайп вправо: Lock (или снять защиту), карточка возвращается на место.
    private func fullPrivacy(velocity: CGFloat = 0) {
        onPrivacy(privacy == .none ? .lock : .none)
        settle(to: 0, velocity: velocity)
    }
}

/// Сдвиг значка от центра капсулы к её краю (progress < 0 — к левому, > 0 — к правому).
/// Анимируется только progress, ширина берётся живой — иначе каждое обновление
/// свайпа обрывало анимацию.
private struct IconShift: ViewModifier, Animatable {
    var progress: CGFloat
    let width: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(x: max(width / 2 - 26, 0) * progress)
    }
}

extension EnvironmentValues {
    /// Счётчик «закрыть открытые свайпы карточек» (листают Spaces или ленту).
    @Entry var swipeReset = 0
}
