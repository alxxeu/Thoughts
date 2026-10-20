import AppKit
import SwiftUI

/// Выбор в обзоре Spaces — отдельно от окна, чтобы проверять тестами.
struct SpaceSwitcherSelection: Equatable {
    var slot: Int

    /// Начальный выбор — текущий Space: панель сразу показывает, где ты сейчас.
    static func initial(active: Int) -> SpaceSwitcherSelection {
        .init(slot: active)
    }

    mutating func move(_ step: Int) {
        slot = BoardViewModel.neighbourSlot(of: slot, step: step)
    }
}

/// Плитка обзора: что показать про Space, без ссылок на живые карточки.
struct SpaceSwitcherTile: Identifiable {
    let slot: Int
    let name: String
    let cardCount: Int
    /// Карточки в долях мини-карты (0…1) и цвет тега.
    let frames: [(rect: CGRect, tag: Color?)]
    let isLocked: Bool
    let isActive: Bool
    var id: Int { slot }

    @MainActor
    static func make(from viewModel: BoardViewModel) -> [SpaceSwitcherTile] {
        viewModel.workspaces.sorted { $0.slot < $1.slot }.map { workspace in
            let cards = viewModel.cards(inSlot: workspace.slot)
            let locked = viewModel.isLocked(slot: workspace.slot)
            return SpaceSwitcherTile(
                slot: workspace.slot,
                name: workspace.name,
                cardCount: cards.count,
                frames: locked ? [] : miniMap(cards),
                isLocked: locked,
                isActive: workspace.slot == viewModel.activeSlot
            )
        }
    }

    /// Карточки в масштабе: от левого верхнего угла канвы до самой дальней карточки.
    private static func miniMap(_ cards: [Card]) -> [(rect: CGRect, tag: Color?)] {
        guard !cards.isEmpty else { return [] }
        let width = max(cards.map { $0.position.x + $0.size.width }.max() ?? 1, 800)
        let height = max(cards.map { $0.position.y + $0.size.height }.max() ?? 1, 500)
        let scale = max(width, height * 1.6)
        return cards.map { card in
            (CGRect(x: card.position.x / scale, y: card.position.y / (scale / 1.6),
                    width: card.size.width / scale, height: card.size.height / (scale / 1.6)),
             card.tagColor?.color)
        }
    }
}

@Observable
final class SpaceSwitcherModel {
    var tiles: [SpaceSwitcherTile] = []
    var selection = SpaceSwitcherSelection(slot: 1)
}

/// Обзор всех Spaces по ⌥Tab, как ⌘Tab для приложений: держишь ⌥ — Tab/⇧Tab,
/// стрелки и цифры двигают выбор от текущего Space; отпустил ⌥ — переход; Esc —
/// отмена. Быстрое нажатие ничего не переключает (выбран текущий).
///
/// Отпускание ⌥ ловим опросом `NSEvent.modifierFlags` (а не flagsChanged): панель
/// может открыться из Finder и стать key не сразу, а опрос видит клавиатуру всегда.
@MainActor
final class SpaceSwitcher {
    static let shared = SpaceSwitcher()

    private let model = SpaceSwitcherModel()
    private var panel: NSPanel?
    private var pollTimer: Timer?
    private var showTask: DispatchWorkItem?
    private var hosting: NSHostingView<SpaceSwitcherView>?
    private var onCommit: ((Int) -> Void)?
    /// Где был курсор при показе: панель появилась под ним — это ещё не выбор мышью.
    private var presentedMouse: CGPoint?
    private(set) var isActive = false

    /// Панель появляется не сразу: случайное быстрое ⌥Tab не мигает панелью.
    private static let showDelay: TimeInterval = 0.15

    /// Открыть (или, если уже открыт, сдвинуть выбор на `step`).
    func trigger(viewModel: BoardViewModel, step: Int = 1, onCommit: @escaping (Int) -> Void) {
        if isActive {
            move(step)
            return
        }
        isActive = true
        self.onCommit = onCommit
        model.tiles = SpaceSwitcherTile.make(from: viewModel)
        model.selection = .initial(active: viewModel.activeSlot)

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkModifiers() }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isActive else { return }
            self.present()
        }
        showTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: work)
    }

    /// Клавиши, пока обзор открыт (из локального монитора приложения). true — съедено.
    func handle(_ event: NSEvent) -> Bool {
        guard isActive, event.type == .keyDown else { return false }
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 48: move(shift ? -1 : 1)                 // Tab
        case 123: move(-1)                            // ←
        case 124: move(1)                             // →
        case 53: finish(commit: false)                // Esc
        case 36, 76: finish(commit: true)             // Return
        default:
            let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
            if let index = digits.firstIndex(of: event.keyCode) {
                model.selection.slot = index + 1
                finish(commit: true)
            }
        }
        return true
    }

    func move(_ step: Int) {
        guard isActive else { return }
        model.selection.move(step)
    }

    private func checkModifiers() {
        guard isActive else { return }
        if !NSEvent.modifierFlags.contains(.option) { finish(commit: true) }
    }

    private func finish(commit: Bool) {
        guard isActive else { return }
        isActive = false
        pollTimer?.invalidate()
        pollTimer = nil
        showTask?.cancel()
        showTask = nil
        panel?.orderOut(nil)
        let slot = model.selection.slot
        let action = onCommit
        onCommit = nil
        if commit { action?(slot) }
    }

    // MARK: - Панель

    private func present() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let tileWidth = min(120, (visible.width - 80) / 9 - 10)
        let size = CGSize(width: tileWidth * 9 + 10 * 8 + 32, height: tileWidth * 0.62 + 64 + 32)
        hosting?.rootView = view(tileWidth: tileWidth)
        presentedMouse = mouse
        panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func view(tileWidth: CGFloat) -> SpaceSwitcherView {
        SpaceSwitcherView(model: model, tileWidth: tileWidth,
                          onHover: { [weak self] slot in
                              // Наведение выбирает, только если мышь сдвинулась после показа.
                              guard let self, NSEvent.mouseLocation != self.presentedMouse else { return }
                              self.presentedMouse = nil
                              self.model.selection.slot = slot
                          },
                          onPick: { [weak self] slot in
                              self?.model.selection.slot = slot
                              self?.finish(commit: true)
                          })
    }

    private func makePanel() -> NSPanel {
        let panel = SwitcherPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                                  backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        // Behind-window блюр, как у Quick Capture.
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: view(tileWidth: 110))
        self.hosting = hosting
        hosting.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: blur.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: blur.bottomAnchor)
        ])
        panel.contentView = blur
        return panel
    }

    /// Может стать key, не активируя приложение (как панель Quick Capture).
    private final class SwitcherPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
}

// MARK: - Вид

struct SpaceSwitcherView: View {
    var model: SpaceSwitcherModel
    var tileWidth: CGFloat
    var onHover: (Int) -> Void
    var onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(model.tiles) { tile in
                tileView(tile)
                    .onHover { if $0 { onHover(tile.slot) } }
                    .onTapGesture { onPick(tile.slot) }
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.25))
    }

    private func tileView(_ tile: SpaceSwitcherTile) -> some View {
        let selected = model.selection.slot == tile.slot
        return VStack(alignment: .leading, spacing: 6) {
            miniMap(tile)
                .frame(width: tileWidth, height: tileWidth * 0.62)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.12), lineWidth: selected ? 2.5 : 0.5)
                )
            HStack(spacing: 4) {
                if tile.isActive {
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                }
                Text(tile.name)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(selected ? 1 : 0.75))
            Text(tile.isLocked ? "Locked \u{00B7} \u{2325}\(tile.slot)" : "\(tile.cardCount) \(tile.cardCount == 1 ? "card" : "cards") \u{00B7} \u{2325}\(tile.slot)")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(width: tileWidth)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func miniMap(_ tile: SpaceSwitcherTile) -> some View {
        if tile.isLocked {
            Image(systemName: "lock.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.5))
        } else {
            GeometryReader { proxy in
                let inset: CGFloat = 6
                let w = proxy.size.width - inset * 2, h = proxy.size.height - inset * 2
                ForEach(Array(tile.frames.enumerated()), id: \.offset) { _, frame in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(frame.tag?.opacity(0.7) ?? Color.white.opacity(0.35))
                        .frame(width: max(2, frame.rect.width * w), height: max(2, frame.rect.height * h))
                        .position(x: inset + (frame.rect.midX) * w, y: inset + (frame.rect.midY) * h)
                }
            }
        }
    }
}
