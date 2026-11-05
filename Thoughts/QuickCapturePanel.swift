import SwiftUI
import AppKit

/// Non-activating панель: получает клавиатуру (canBecomeKey), но не
/// активирует Thoughts и не поднимает главное окно — как Spotlight. Это
/// важно для Desktop Overlay, где главное окно лежит ниже всех приложений,
/// и поднимать его ради одной заметки было бы неправильно.
private final class QuickCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Черновик и видимость панели — наблюдаются SwiftUI-контентом панели.
@Observable
private final class QuickCaptureModel {
    var draft = ""
    var isPresented = false
    /// Тело раскрыто (вниз из нотча); false — свёрнуто в сам нотч. Анимируется отдельно от isPresented.
    var isExpanded = false
    /// 0 — свёрнуто в нотч, 1 — раскрыто. Один и тот же прогресс ведёт и чёрное тело (SwiftUI), и стеклянную
    /// подложку (маска AppKit), поэтому они всегда одного размера.
    var progress: CGFloat = 0
    /// Space, куда уйдёт карточка; nil — активный (выбор сбрасывается при каждом показе).
    var targetSlot: Int?
    var geometry = NotchGeometry.fallback
}

/// Размеры нотча экрана: с вырезом — железный нотч, без выреза — имитация у верхнего края
/// (чёрная «таблетка» высотой со строку меню).
struct NotchGeometry: Equatable {
    var width: CGFloat
    var height: CGFloat

    static let fallback = NotchGeometry(width: 180, height: 32)

    static func of(_ screen: NSScreen?) -> NotchGeometry {
        guard let screen else { return fallback }
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NotchGeometry(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(width: 180, height: max(menuBar, 24))
    }
}

/// Глобальный хоткей Quick Capture (по умолчанию ⌃⌥N, настраивается в
/// Settings → Shortcuts) и плавающая панель записи. Return сохраняет
/// карточку в первое свободное место активного Space, Esc закрывает и
/// сбрасывает текст, клик мимо закрывает, сохраняя черновик.
final class QuickCaptureController: NSObject, NSWindowDelegate {
    static let shared = QuickCaptureController()

    private let settings = QuickCaptureSettings.shared
    private let model = QuickCaptureModel()
    private weak var viewModel: BoardViewModel?
    private var hotKeyToken: HotKeyToken?
    private var panel: QuickCapturePanel?
    private var closeTask: Task<Void, Never>?
    /// Стеклянная подложка (размытие того, что за окном) под нижней частью тела; верх закрыт чёрным.
    private var glass: NSVisualEffectView?

    /// Тело «острова» и вогнутые «уши» по бокам вверху (как у расширения нотча).
    private static let bodyWidth: CGFloat = 480
    private static let flare: CGFloat = 12
    /// Верхний зазор 4 + поле 96 + зазор 10 + строка подсказок 14 + нижний отступ ~16 до низа текста (как боковой).
    private static let contentHeight: CGFloat = 138
    /// Прозрачный запас вокруг тела (по бокам и снизу) под мягкую тень.
    static let shadowInset: CGFloat = 52
    private static var panelWidth: CGFloat { bodyWidth + 2 * flare + 2 * shadowInset }

    private override init() {}

    func start(viewModel: BoardViewModel) {
        self.viewModel = viewModel
        updateHotKey()
    }

    // MARK: - Hotkey

    /// Перерегистрирует хоткей по текущим настройкам. Возвращает ошибку,
    /// если сочетание занято другим приложением.
    @discardableResult
    func updateHotKey() -> GlobalHotKeyManager.RegistrationError? {
        suspendHotKey()
        guard settings.isEnabled else { return nil }

        let shortcut = settings.shortcut
        switch GlobalHotKeyManager.shared.register(
            keyCode: shortcut.keyCode,
            modifiers: shortcut.carbonModifiers,
            action: { [weak self] in self?.toggle() }
        ) {
        case .success(let token):
            hotKeyToken = token
            return nil
        case .failure(let error):
            return error
        }
    }

    /// Пробует новое сочетание; если оно занято — возвращает прежнее и
    /// сообщает об ошибке (рекордер в Settings показывает предупреждение).
    @discardableResult
    func apply(_ shortcut: HotKeyShortcut) -> GlobalHotKeyManager.RegistrationError? {
        let previous = settings.shortcut
        settings.shortcut = shortcut
        guard let error = updateHotKey() else { return nil }
        settings.shortcut = previous
        updateHotKey()
        return error
    }

    /// На время записи нового сочетания в Settings — иначе нажатие текущего
    /// хоткея перехватил бы Carbon, и рекордер его бы не увидел.
    func suspendHotKey() {
        if let hotKeyToken {
            GlobalHotKeyManager.shared.unregister([hotKeyToken])
        }
        hotKeyToken = nil
    }

    // MARK: - Panel

    func toggle() {
        if panel?.isVisible == true, model.isPresented {
            close(discardingDraft: false)
        } else {
            show()
        }
    }

    func show() {
        guard viewModel != nil else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        closeTask?.cancel()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let geometry = NotchGeometry.of(screen)
        model.geometry = geometry
        if let frame = screen?.frame {
            let size = CGSize(width: Self.panelWidth, height: geometry.height + Self.contentHeight + Self.shadowInset)
            panel.setFrame(CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height), display: false)
        }

        model.isPresented = true
        model.isExpanded = false
        model.targetSlot = nil
        setProgress(0)
        panel.makeKeyAndOrderFront(nil)
        // Раскрытие — со следующего кадра, чтобы анимация стартовала из свёрнутого нотча.
        DispatchQueue.main.async { [weak self] in
            self?.model.isExpanded = true
            self?.animateProgress(to: 1, duration: 0.24)
        }
    }

    // MARK: - Анимация раскрытия

    private var displayLink: CADisplayLink?

    /// easeOutCubic по прогрессу: без перелёта, поэтому кромка у тела не «прыгает» на конце.
    private func animateProgress(to target: CGFloat, duration: TimeInterval, completion: (() -> Void)? = nil) {
        displayLink?.invalidate()
        let from = model.progress
        let start = CACurrentMediaTime()
        guard let view = panel?.contentView, duration > 0, from != target else {
            setProgress(target)
            completion?()
            return
        }
        let driver = ProgressDriver { [weak self] in
            guard let self else { return }
            let t = min(1, (CACurrentMediaTime() - start) / duration)
            let eased = 1 - pow(1 - t, 3)
            self.setProgress(from + (target - from) * eased)
            if t >= 1 {
                self.displayLink?.invalidate()
                self.displayLink = nil
                completion?()
            }
        }
        let link = view.displayLink(target: driver, selector: #selector(ProgressDriver.tick))
        objc_setAssociatedObject(link, &Self.driverKey, driver, .OBJC_ASSOCIATION_RETAIN)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private static var driverKey = 0

    private final class ProgressDriver: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func tick() { action() }
    }

    /// Прогресс применяется сразу к SwiftUI-телу и к маске стекла.
    private func setProgress(_ value: CGFloat) {
        model.progress = value
        guard let panel, let glass else { return }
        let size = panel.frame.size
        let notch = model.geometry
        let fullSize = CGSize(width: size.width - 2 * Self.shadowInset, height: size.height - Self.shadowInset)
        let width = notch.width + (fullSize.width - notch.width) * value
        let height = notch.height + (fullSize.height - notch.height) * value
        let rect = CGRect(x: (size.width - width) / 2, y: 0, width: width, height: height)
        let path = NotchIslandShape(flare: Self.flare * value, radius: 10 + 14 * value).path(in: rect).cgPath
        glass.maskImage = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(path)
            context.fillPath()
            return true
        }
        glass.alphaValue = min(1, value / 0.5)
    }

    func close(discardingDraft: Bool) {
        if discardingDraft {
            model.draft = ""
        }
        guard model.isPresented else { return }
        model.isPresented = false
        model.isExpanded = false
        closeTask?.cancel()
        // Сворачивается тем же прогрессом (стекло и тело вместе), окно прячется в конце.
        animateProgress(to: 0, duration: 0.18) { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }

    /// Системное меню выбора Space под подписью «⌥⇅ Space» (клик и ⌥↑/↓ открывают одно и то же).
    private func showSpaceMenu() {
        guard let viewModel, let view = panel?.contentView else { return }
        let menu = NSMenu()
        let current = model.targetSlot ?? viewModel.activeSlot
        for workspace in viewModel.workspaces.sorted(by: { $0.slot < $1.slot }) {
            let item = NSMenuItem(title: "\(workspace.slot)  \(workspace.name)", action: #selector(pickSpace(_:)), keyEquivalent: "")
            item.target = self
            item.tag = workspace.slot
            item.state = workspace.slot == current ? .on : .off
            if viewModel.isLocked(slot: workspace.slot) {
                item.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")
            }
            menu.addItem(item)
        }
        // Под подписью: слева 5 + 9 от края тела, сверху — под строкой подсказок.
        let point = CGPoint(x: Self.shadowInset + Self.flare + 5 + 9, y: model.geometry.height + 4 + 96 + 10 + 14 + 4)
        menu.popUp(positioning: nil, at: point, in: view)
    }

    @objc private func pickSpace(_ sender: NSMenuItem) {
        model.targetSlot = sender.tag
    }

    private func submit() {
        let text = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let viewModel else { return }
        let card = viewModel.addQuickCaptureCard(text: text, slot: model.targetSlot)
        close(discardingDraft: true)
        // Если канва сейчас видна, новая карточка коротко подсвечивается —
        // CardView подписан на .highlightCard (как для Spotlight).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .highlightCard, object: card.id)
        }
    }

    private func makePanel() -> QuickCapturePanel {
        let panel = QuickCapturePanel(
            contentRect: CGRect(x: 0, y: 0, width: Self.panelWidth, height: 150),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )
        // Над строкой меню: тело закрывает её участок и продолжает нотч.
        panel.level = .statusBar + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // Приложение в момент показа обычно неактивно — с дефолтным true
        // панель тут же пряталась бы вместе с "деактивацией".
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.delegate = self

        let hosting = NSHostingView(rootView: QuickCaptureView(
            model: model,
            viewModel: viewModel,
            bodyWidth: Self.bodyWidth,
            flare: Self.flare,
            contentHeight: Self.contentHeight,
            shadowInset: Self.shadowInset,
            onSubmit: { [weak self] in self?.submit() },
            onCancel: { [weak self] in self?.close(discardingDraft: true) },
            onOpenSpaceMenu: { [weak self] in self?.showSpaceMenu() }
        ))
        let container = NSView()
        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .vibrantDark)
        glass.alphaValue = 0
        self.glass = glass
        for view in [glass, hosting] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
        panel.contentView = container
        return panel
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        close(discardingDraft: false)
    }
}

/// Чёрное тело, продолжающее нотч: вогнутые «уши» вверху по бокам и скруглённый низ.
/// `flare` и `radius` анимируются: в свёрнутом виде (сам нотч) «ушей» нет.
private struct NotchIslandShape: Shape {
    var flare: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, radius) }
        set { flare = newValue.first; radius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let f = flare, rad = min(radius, r.height / 2, (r.width - 2 * f) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - f, y: r.minY + f), control: CGPoint(x: r.maxX - f, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - f, y: r.maxY - rad))
        p.addArc(center: CGPoint(x: r.maxX - f - rad, y: r.maxY - rad), radius: rad, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + f + rad, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + f + rad, y: r.maxY - rad), radius: rad, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + f, y: r.minY + f))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY), control: CGPoint(x: r.minX + f, y: r.minY))
        p.closeSubpath()
        return p
    }
}

private struct QuickCaptureView: View {
    var model: QuickCaptureModel
    var viewModel: BoardViewModel?
    var bodyWidth: CGFloat
    var flare: CGFloat
    var contentHeight: CGFloat
    var shadowInset: CGFloat
    static let hintHeight: CGFloat = 14
    var onSubmit: () -> Void
    var onCancel: () -> Void
    var onOpenSpaceMenu: () -> Void

    var body: some View {
        let typography = viewModel?.appearanceSettings.cardTypography
            ?? AppearanceSettings.shared.cardTypography
        let notch = model.geometry
        let expanded = model.isExpanded
        let p = model.progress
        let fullWidth = bodyWidth + 2 * flare
        let fullHeight = notch.height + contentHeight

        ZStack(alignment: .top) {
            // Свёрнутое тело — ровно размер нотча (на железном невидимо), раскрытое — вниз и вширь.
            // Верх — плотный чёрный (сливается с нотчем, границы не видно), к низу прозрачнее:
            // сквозь него проступает стеклянная подложка (размытие того, что за панелью).
            let bodyW = notch.width + (fullWidth - notch.width) * p
            let bodyH = notch.height + (fullHeight - notch.height) * p
            // Мягкая тень под телом: только снаружи формы (внутри стекло должно оставаться прозрачным).
            let shadowShape = NotchIslandShape(flare: flare * p, radius: 10 + 14 * p)
            shadowShape
                .fill(Color.black.opacity(0.36 * p))
                .frame(width: bodyW, height: bodyH)
                .offset(y: 8)
                .blur(radius: 14)
                .mask {
                    Rectangle()
                        .frame(width: bodyW + 160, height: bodyH + 160)
                        .overlay {
                            shadowShape.fill(Color.black)
                                .frame(width: bodyW, height: bodyH)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }

            NotchIslandShape(flare: flare * p, radius: 10 + 14 * p)
                .fill(LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: min(1, (notch.height + 26) / max(1, bodyH))),
                        .init(color: Color.black.opacity(0.28), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
                .overlay {
                    // Кромка «стекла»: только внутри формы, ярче всего по низу и гаснет к верху
                    // (у нотча её нет). Мягкое свечение внутрь + тонкая яркая линия.
                    let shape = NotchIslandShape(flare: flare * p, radius: 10 + 14 * p)
                    // Простой белый, яркость 0.16 (складывается со светом тела через plusLighter).
                    let tint = Color.white.opacity(0.16)
                    let bottomFade = LinearGradient(stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: Color.black.opacity(0.45), location: 0.75),
                        .init(color: .black, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    ZStack {
                        shape.stroke(tint, lineWidth: 7)
                            .blur(radius: 5)
                            .opacity(0.7)
                            .mask(bottomFade)
                        shape.stroke(tint, lineWidth: 1.5)
                            .mask(bottomFade)
                    }
                    .clipShape(shape)
                    .blendMode(.plusLighter)
                    .opacity(p)
                }
                .frame(width: bodyW, height: bodyH)

            VStack(alignment: .leading, spacing: 10) {
                AIPromptTextView(
                    text: Binding(get: { model.draft }, set: { model.draft = $0 }),
                    shouldFocus: expanded && p > 0.5,
                    onSend: onSubmit,
                    font: typography.font,
                    // Тело всегда чёрное — текст светлый, а не цвет карточек (он может быть тёмным).
                    textColor: .white,
                    sendKeyBinding: .returnSends,
                    onEscape: onCancel,
                    onOptionArrow: { _ in onOpenSpaceMenu() }
                )
                .frame(height: 96)
                .overlay(alignment: .topLeading) {
                    if model.draft.isEmpty {
                        Text("Capture a thought\u{2026}")
                            .font(Font(typography.font as CTFont))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .padding(.leading, 11)
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }
                }

                HStack(spacing: 6) {
                    spaceMenu
                    Spacer()
                    HStack(spacing: 4) {
                        hintSymbol("shift")
                        hintSymbol("return")
                        Text("new line")
                    }
                    Text("\u{00B7}")
                    HStack(spacing: 4) {
                        hintSymbol("return")
                        Text("save")
                    }
                }
                .frame(height: Self.hintHeight)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
                // Слева 9: у символа ⌥ и кнопки меню свой внутренний отступ ~2.
                .padding(.leading, 9)
                .padding(.trailing, 11)
            }
            // Тело до текста — 16 везде: у поля 5 + 11 (отступ и lineFragmentPadding самого NSTextView), у подсказок 5 + 11.
            .padding(.horizontal, flare + 5)
            .padding(.top, notch.height + 4)
            .frame(width: fullWidth, height: fullHeight, alignment: .top)
            // Содержимое проявляется, когда тело уже раскрылось.
            .opacity(expanded ? max(0, min(1, (p - 0.55) / 0.35)) : max(0, min(1, (p - 0.8) / 0.2)))
        }
        .frame(width: fullWidth + 2 * shadowInset, height: fullHeight + shadowInset, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    /// Символ клавиши в подсказках: мелкий и серый, как остальные подсказки.
    private func hintSymbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.5))
    }

    private var targetSlot: Int { model.targetSlot ?? viewModel?.activeSlot ?? 1 }

    private func name(of slot: Int) -> String {
        viewModel?.workspaces.first { $0.slot == slot }?.name ?? Workspace.defaultName(forSlot: slot)
    }

    /// «⌥⇅ Space ⌄»: по клику или ⌥↑/↓ открывается системное меню выбора Space (см. showSpaceMenu).
    private var spaceMenu: some View {
        Button(action: onOpenSpaceMenu) {
            HStack(spacing: 4) {
                hintSymbol("option")
                hintSymbol("arrow.up.arrow.down")
                if viewModel?.isLocked(slot: targetSlot) == true {
                    Image(systemName: "lock.fill")
                }
                Text(name(of: targetSlot))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
