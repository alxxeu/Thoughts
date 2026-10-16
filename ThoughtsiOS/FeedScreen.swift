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

    var body: some View {
        GeometryReader { geo in
        // Страницы Spaces — горизонтальная прокрутка без обрезки (страничный TabView
        // обрезал ленту). Настоящие бары лежат поверх и не уезжают при свайпе, а
        // каждой ленте даны прозрачные бары той же высоты — они включают системный
        // scroll edge (мягкое затухание с размытием).
        let insets = EdgeInsets(top: geo.safeAreaInsets.top + 56, leading: 0,
                                bottom: geo.safeAreaInsets.bottom + bottomBarHeight, trailing: 0)
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(board.workspaces) { workspace in
                    FeedList(board: board, slot: workspace.slot, revealed: revealed, insets: insets,
                             onOpen: { editing = EditorTarget(card: $0, detent: .medium) },
                             onReveal: reveal,
                             onCollapse: { collapsed in withAnimation(.snappy) { spacesCollapsed = collapsed } })
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
        }
        // Бары — поверх, в безопасной зоне (клавиатура поднимает поле ввода сама).
        .overlay(alignment: .top) { HStack { Spacer(); moreButton }.padding(.top, 6) }
        .overlay(alignment: .bottom) {
            bottomBar.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomBarHeight = $0 }
        }
        .background(Theme.background.ignoresSafeArea())
        // Клавиатура закрывается прокруткой ленты и кнопкой над ней.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { composerFocused = false } label: { Image(systemName: "keyboard.chevron.compact.down") }
            }
        }
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
            Composer(text: $draft, focused: $composerFocused, onSend: send, onExpand: expand)
            if !composerFocused {
                SpacesBar(workspaces: board.workspaces, slot: $slot, collapsed: spacesCollapsed,
                          onRename: { renaming = $0; newName = $0.name })
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .animation(.snappy, value: composerFocused)
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
    /// Высота баров экрана (статус-бар + «…» сверху, поле ввода + Spaces снизу).
    let insets: EdgeInsets
    var onOpen: (Card) -> Void
    var onReveal: (Card) -> Void
    var onCollapse: (Bool) -> Void

    /// Порядок замораживается: лента не перестраивается под пальцем — новый
    /// порядок при открытии Space и при возврате из редактора.
    @State private var order: [UUID] = []

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
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) { board.deleteCard(id: card.id) }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
        }
        .listStyle(.plain)
        .safeAreaBar(edge: .top, spacing: 0) { Color.clear.frame(height: insets.top) }
        .safeAreaBar(edge: .bottom, spacing: 0) { Color.clear.frame(height: insets.bottom) }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .defaultScrollAnchor(.bottom)
        // Полоса Spaces сворачивается в точки, когда листаем вверх, к старым.
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height > 120
        } action: { _, away in onCollapse(away) }
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
                VStack(spacing: 8) {
                    if isLong {
                        Button(action: onExpand) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.secondary)
                                .frame(width: 32, height: 32)
                        }
                        Spacer(minLength: 0)
                    }
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Theme.accent, in: .circle)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, hasText ? 8 : 18)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
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
    var onRename: (Workspace) -> Void

    var body: some View {
        if collapsed {
            HStack(spacing: 8) {
                ForEach(workspaces) { ws in
                    Capsule()
                        .fill(ws.slot == slot ? Theme.text : Theme.secondary)
                        .frame(width: ws.slot == slot ? 16 : 6, height: 6)
                }
            }
            .frame(height: 20)
            .transition(.opacity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(workspaces) { ws in
                            Button { withAnimation(.snappy) { slot = ws.slot } } label: {
                                Text(ws.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(ws.slot == slot ? Theme.text : Theme.secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background {
                                        if ws.slot == slot { Capsule().fill(.clear).glassEffect(.regular, in: .capsule) }
                                    }
                            }
                            .buttonStyle(.plain)
                            .id(ws.slot)
                            .contextMenu { Button("Rename…", systemImage: "pencil") { onRename(ws) } }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onChange(of: slot) { _, s in withAnimation { proxy.scrollTo(s, anchor: .center) } }
            }
            .frame(height: 40)
            .transition(.opacity)
        }
    }
}
