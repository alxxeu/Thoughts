import SwiftUI
import AppKit

/// Свайп по панели Space: сама панель тянется за пальцем «резинкой» (чем дальше,
/// тем сильнее сопротивление), Spaces при этом не рендерятся; отпустили за порогом —
/// панель возвращается на место и Space меняется на соседний.
enum SpaceBarSwipe {
    /// Возврат панели на место — без пружины, в тон остальным анимациям (easeOut).
    static let returnAnimation = Animation.easeOut(duration: 0.25)
    /// Насколько далеко панель может уехать при бесконечном жесте.
    static let maxPull: CGFloat = 46
    /// Сколько нужно протянуть (сырой сдвиг жеста), чтобы Space сменился.
    static let threshold: CGFloat = 64

    /// Сдвиг панели от сырого сдвига жеста: почти 1:1 у начала, дальше затухает.
    static func resisted(_ raw: CGFloat) -> CGFloat {
        let x = abs(raw)
        let pulled = maxPull * (1 - 1 / (x / (maxPull * 1.4) + 1))
        return raw < 0 ? -pulled : pulled
    }

    enum Destination: Equatable { case desktop, space(Int) }

    /// Куда ведёт шаг свайпа. С включённым Desktop Overlay Desktop mode — десятая позиция
    /// кольца перед Space 1: Space 1 ← → Desktop, Desktop ← → Space 9. `current` nil — мы на столе.
    static func destination(current: Int?, step: Int, hasDesktop: Bool) -> Destination {
        if hasDesktop {
            let index = (((current ?? 0) + step) % 10 + 10) % 10
            return index == 0 ? .desktop : .space(index)
        }
        return .space((((current ?? 1) - 1 + step) % 9 + 9) % 9 + 1)
    }

    /// Оттяжка точки по сдвигу жеста: −1…1 (минус — к следующему Space), 1 — порог.
    static func dotPull(forRaw raw: CGFloat) -> CGFloat {
        max(-1, min(raw / threshold, 1))
    }

    /// Шаг Space по сдвигу: влево — следующий (+1), вправо — предыдущий (-1), 0 — не дотянули.
    static func step(forRaw raw: CGFloat) -> Int {
        guard abs(raw) >= threshold else { return 0 }
        return raw < 0 ? 1 : -1
    }
}

/// Ловит двупальцевый свайп (колесо/трекпад) над панелью, не мешая кликам: view
/// «видит» мышь только пока приходит scrollWheel.
struct SpaceBarScrollCatcher: NSViewRepresentable {
    /// Накопленный горизонтальный сдвиг и признак конца жеста.
    var onScroll: (CGFloat, Bool) -> Void
    /// Курсор над панелью — следим сами (NSTrackingArea .activeAlways): у панели без фокуса
    /// SwiftUI `.onHover` не срабатывает.
    var onHover: ((Bool) -> Void)?

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onHover = onHover
    }

    final class CatcherView: NSView {
        var onScroll: (CGFloat, Bool) -> Void = { _, _ in }
        var onHover: ((Bool) -> Void)?
        private var total: CGFloat = 0

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }

        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }

        private var monitor: Any?
        private var totalY: CGFloat = 0

        override func scrollWheel(with event: NSEvent) {
            // Колесо мыши (без фаз) и инерцию после жеста не считаем.
            guard !event.phase.isEmpty, event.momentumPhase.isEmpty else {
                nextResponder?.scrollWheel(with: event)
                return
            }
            if monitor == nil {
                // Жест берём с самого начала (began/mayBegin приходят почти без сдвига, по ним
                // направление не понять): иначе событие уходит дальше по цепочке, система
                // привязывает жест к другому view и остальные события сюда не приходят.
                // Вертикальный жест отсеем уже в `handle`.
                guard event.phase.contains(.began) || event.phase.contains(.mayBegin)
                        || abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else {
                    nextResponder?.scrollWheel(with: event)
                    return
                }
                total = 0
                totalY = 0
                // Дальше жест ведём сами, где бы ни был курсор: панель едет из-под него, и без
                // этого события ушли бы в другое view, а жест оборвался.
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    self?.handle(event)
                    return nil
                }
            }
            handle(event)
        }

        private var idleFinish: DispatchWorkItem?

        private func handle(_ event: NSEvent) {
            guard event.momentumPhase.isEmpty else { return }
            total += event.scrollingDeltaX
            totalY += event.scrollingDeltaY
            let ended = event.phase == .ended || event.phase == .cancelled
            idleFinish?.cancel()
            // Жест пошёл вверх-вниз — это не наш свайп: отпускаем без переключения.
            if abs(totalY) > abs(total) + 20 { total = 0 }
            if ended {
                finish()
            } else {
                onScroll(total, false)
                // Конец жеста может не прийти (системный жест, меню-бар в fullscreen забрал
                // события): тогда по тишине в 0.3 с считаем жест законченным, иначе панель
                // остаётся сдвинутой, а Space не меняется.
                let work = DispatchWorkItem { [weak self] in self?.finish() }
                idleFinish = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }
        }

        private func finish() {
            guard monitor != nil else { return }
            onScroll(total, true)
            total = 0
            totalY = 0
            idleFinish?.cancel()
            idleFinish = nil
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// Общий вид панели Space: цвет текста — как у карточек, подложка под его яркость.
enum SpaceBarStyle {
    static func tint(ink: NSColor, isDark: Bool) -> Color {
        ink.isLight
            ? Color.black.opacity(isDark ? 0.1 : 0.5)
            : Color.white.opacity(isDark ? 0.5 : 0.3)
    }
}

/// Панель Space в Desktop mode (⌥D): окно с карточками там ниже иконок стола и не ловит
/// мышь, поэтому имя Space, точки и свайп живут в маленькой отдельной панели. Свайп
/// выходит из Desktop mode в соседний Space.
@MainActor
final class DesktopSpaceBarPanel {
    static let shared = DesktopSpaceBarPanel()
    private weak var viewModel: BoardViewModel?
    private var panel: NSPanel?

    func attach(viewModel: BoardViewModel) { self.viewModel = viewModel }

    /// Показывает панель, пока включён Desktop mode; иначе прячет.
    func update() {
        guard let viewModel, viewModel.desktopOverlay.isEnabled, viewModel.desktopOverlay.isDesktopModeActive else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel(viewModel)
        self.panel = panel
        guard let screen = NSScreen.main, let hosting = panel.contentView as? FirstClickHostingView else { return }
        hosting.rootView = DesktopSpaceBarView(viewModel: viewModel)
        let size = hosting.fittingSize
        let top = max(BoardViewModel.screenTopInset + 12 - 24, 0) // минус внутренний отступ панели
        panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2,
                              y: screen.frame.maxY - top - size.height,
                              width: size.width, height: size.height), display: true)
        panel.orderFront(nil)
    }

    private func makePanel(_ viewModel: BoardViewModel) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Над иконками стола, ниже окон приложений: стол остаётся рабочим.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.contentView = FirstClickHostingView(rootView: DesktopSpaceBarView(viewModel: viewModel))
        return panel
    }
}

private struct DesktopSpaceBarView: View {
    var viewModel: BoardViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var swipeRaw: CGFloat = 0
    /// Оттяжка точки (−1…1); после смены Space сбрасывается без анимации — точка уже «дотянулась».
    @State private var dotPull: CGFloat = 0
    @State private var isHovering = false

    private var inkNSColor: NSColor { viewModel.appearanceSettings.cardTypography.color.withAlphaComponent(1) }
    private var ink: Color { Color(nsColor: inkNSColor) }

    var body: some View {
        Text("Desktop")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(ink.opacity(0.9))
            .fixedSize()
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(SpaceBarStyle.tint(ink: inkNSColor, isDark: colorScheme == .dark))))
        // Точки под капсулой, как на Spaces: по наведению и во время свайпа; на столе горит «стол».
        .overlay(alignment: .bottom) { dots.offset(y: 12) }
        // Жест не привязан к капсуле: ловит и вокруг неё.
        .overlay { SpaceBarScrollCatcher(onScroll: { total, ended in update(total, ended: ended) }, onHover: { isHovering = $0 }).padding(-24) }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { update($0.translation.width, ended: false) }
                .onEnded { update($0.translation.width, ended: true) }
        )
        .offset(x: SpaceBarSwipe.resisted(swipeRaw))
        // Запас под «резинку» и точки снизу, иначе панель обрежется границей окна.
        .padding(.horizontal, SpaceBarSwipe.maxPull + 24)
        .padding(.vertical, 24)
    }

    private var dots: some View {
        SpaceBarDots(activeSlot: nil, hasDesktop: true, ink: ink, pull: dotPull)
            .opacity(isHovering || swipeRaw != 0 ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: isHovering || swipeRaw != 0)
            .allowsHitTesting(false)
    }

    private func update(_ raw: CGFloat, ended: Bool) {
        if !ended {
            swipeRaw = raw
            dotPull = SpaceBarSwipe.dotPull(forRaw: raw)
            return
        }
        let step = SpaceBarSwipe.step(forRaw: raw)
        withAnimation(SpaceBarSwipe.returnAnimation) { swipeRaw = 0 }
        if step != 0 {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { dotPull = 0 }
        } else {
            withAnimation(SpaceBarSwipe.returnAnimation) { dotPull = 0 }
        }
        guard step != 0 else { return }
        // Со стола: влево — Space 1, вправо — Space 9 (кольцо из десяти позиций).
        if case .space(let slot) = SpaceBarSwipe.destination(current: nil, step: step, hasDesktop: true) {
            viewModel.desktopOverlay.isDesktopModeActive = false
            NotificationCenter.default.post(name: .switchWorkspace, object: slot)
        }
    }
}

/// Панель без фокуса иначе тратит первое нажатие на «захват» окна и не начинает перетаскивание.
private final class FirstClickHostingView: NSHostingView<DesktopSpaceBarView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Точки позиций под капсулой: при включённом Desktop Overlay первой стоит «стол»
/// (квадратик), затем девять Spaces; текущая ярче. `activeSlot` nil — мы на столе.
/// `pull` (−1…1, минус — к следующей) — оттяжка свайпом: яркая точка тянется к соседней
/// «каплей» (перемычка сужается), соседняя разгорается; отпустили за порогом — точка
/// остаётся там, где её тянули, а Space меняется.
struct SpaceBarDots: View {
    var activeSlot: Int?
    var hasDesktop: Bool
    var ink: Color
    var pull: CGFloat = 0

    private static let radius: CGFloat = 2.5
    private static let pitch: CGFloat = 9.5

    private var positions: [Int?] { (hasDesktop ? [nil] : []) + (1...9).map { Optional($0) } }
    private var currentIndex: Int { positions.firstIndex { $0 == activeSlot } ?? 0 }
    /// Центры точек по x (после «стола» чуть шире зазор).
    private var centers: [CGFloat] {
        positions.indices.map { Self.radius + CGFloat($0) * Self.pitch + (hasDesktop && $0 > 0 ? 2 : 0) }
    }

    /// Соседняя позиция в сторону оттяжки (в ряду; у края — nil: через край тянется «стол»/Space 9 слабее).
    private var targetIndex: Int? {
        guard pull != 0 else { return nil }
        let t = currentIndex + (pull < 0 ? 1 : -1)
        return positions.indices.contains(t) ? t : nil
    }

    var body: some View {
        let xs = centers
        let amount = min(abs(pull), 1)
        ZStack(alignment: .topLeading) {
            ForEach(positions.indices, id: \.self) { index in
                let isDesktop = positions[index] == nil
                // Соседняя разгорается и к концу оттяжки прячется под головкой капли (та садится ровно на неё).
                let lit = index == targetIndex ? (0.35 + 0.4 * amount) * (1 - max(0, (amount - 0.7) / 0.3)) : (index == currentIndex ? 0 : 0.35)
                RoundedRectangle(cornerRadius: isDesktop ? 1.2 : Self.radius)
                    .fill(ink.opacity(lit))
                    .frame(width: 4, height: 4)
                    .position(x: xs[index], y: Self.radius)
            }
            DotPullShape(centers: xs, current: currentIndex, target: targetIndex, pull: amount, radius: Self.radius,
                         fallbackDirection: pull < 0 ? 1 : -1)
                .fill(ink.opacity(0.9))
        }
        .frame(width: (xs.last ?? 0) + Self.radius, height: Self.radius * 2)
    }
}

/// Яркая точка, тянущаяся к соседней: исходная сжимается, перемычка тоньше, головка едет.
private struct DotPullShape: Shape {
    var centers: [CGFloat]
    var current: Int
    var target: Int?
    var pull: CGFloat
    var radius: CGFloat
    var fallbackDirection: CGFloat

    var animatableData: CGFloat {
        get { pull }
        set { pull = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard centers.indices.contains(current) else { return Path() }
        let from = centers[current]
        let y = radius
        // У края ряда тянем на полшага в пустоту, не дальше.
        let distance = target.map { centers[$0] - from } ?? fallbackDirection * 4.5
        let headX = from + distance * pull
        let tailRadius = radius * (1 - 0.5 * pull)
        let headRadius = radius * (1 + 0.12 * pull)
        let tail = CGPoint(x: from, y: y), head = CGPoint(x: headX, y: y)
        // union, а не общий Path: у перемычки и кружков разный обход, и при сложении по
        // правилу ненулевой обмотки в местах наложения появлялись «дырки».
        var path = Path(ellipseIn: CGRect(x: tail.x - tailRadius, y: y - tailRadius, width: tailRadius * 2, height: tailRadius * 2))
        path = path.union(Path(ellipseIn: CGRect(x: head.x - headRadius, y: y - headRadius, width: headRadius * 2, height: headRadius * 2)))
        if let neck = Self.neck(tail, tailRadius, head, headRadius) { path = path.union(neck) }
        return path
    }

    /// «Капля» между двумя кружками (классические метаболлы: касательные с общей дугой и
    /// кривые Безье, перемычка тоньше посередине). Дальше `reach` перемычка рвётся — кружки
    /// остаются раздельными.
    private static func neck(_ c1: CGPoint, _ r1: CGFloat, _ c2: CGPoint, _ r2: CGFloat) -> Path? {
        let v: CGFloat = 0.5, handleRate: CGFloat = 2.4
        let dx = c2.x - c1.x, dy = c2.y - c1.y
        let d = (dx * dx + dy * dy).squareRoot()
        let reach = (r1 + r2) * 2.0
        guard d > abs(r1 - r2), d < reach else { return nil }
        var u1: CGFloat = 0, u2: CGFloat = 0
        if d < r1 + r2 {
            u1 = acos(min(max((r1 * r1 + d * d - r2 * r2) / (2 * r1 * d), -1), 1))
            u2 = acos(min(max((r2 * r2 + d * d - r1 * r1) / (2 * r2 * d), -1), 1))
        }
        let between = atan2(dy, dx)
        let maxSpread = acos(min(max((r1 - r2) / d, -1), 1))
        let a1 = between + u1 + (maxSpread - u1) * v
        let a2 = between - u1 - (maxSpread - u1) * v
        let a3 = between + .pi - u2 - (.pi - u2 - maxSpread) * v
        let a4 = between - .pi + u2 + (.pi - u2 - maxSpread) * v
        func point(_ c: CGPoint, _ r: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)) }
        let p1a = point(c1, r1, a1), p1b = point(c1, r1, a2), p2a = point(c2, r2, a3), p2b = point(c2, r2, a4)
        let chord = ((p1a.x - p2a.x) * (p1a.x - p2a.x) + (p1a.y - p2a.y) * (p1a.y - p2a.y)).squareRoot()
        var d2 = min(v * handleRate, chord / (r1 + r2))
        d2 *= min(1, d * 2 / (r1 + r2))
        let h1 = r1 * d2, h2 = r2 * d2
        let h1a = point(p1a, h1, a1 - .pi / 2), h1b = point(p1b, h1, a2 + .pi / 2)
        let h2a = point(p2a, h2, a3 + .pi / 2), h2b = point(p2b, h2, a4 - .pi / 2)
        var path = Path()
        path.move(to: p1a)
        path.addCurve(to: p2a, control1: h1a, control2: h2a)
        path.addLine(to: p2b)
        path.addCurve(to: p1b, control1: h2b, control2: h1b)
        path.closeSubpath()
        return path
    }
}
