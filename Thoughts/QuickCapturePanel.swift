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
}

/// Глобальный хоткей Quick Capture (по умолчанию ⌃⌥⌘N, настраивается в
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

    private static let panelWidth: CGFloat = 480

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
        if panel?.isVisible == true {
            close(discardingDraft: false)
        } else {
            show()
        }
    }

    func show() {
        guard viewModel != nil else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let size = panel.contentView?.fittingSize ?? CGSize(width: Self.panelWidth, height: 150)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let origin = CGPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - visible.height * 0.28 - size.height
            )
            panel.setFrame(CGRect(origin: origin, size: size), display: false)
        }

        model.isPresented = true
        panel.makeKeyAndOrderFront(nil)
    }

    func close(discardingDraft: Bool) {
        if discardingDraft {
            model.draft = ""
        }
        model.isPresented = false
        panel?.orderOut(nil)
    }

    private func submit() {
        let text = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let viewModel else { return }
        let card = viewModel.addQuickCaptureCard(text: text)
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
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // Приложение в момент показа обычно неактивно — с дефолтным true
        // панель тут же пряталась бы вместе с "деактивацией".
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        // Настоящий behind-window блюр (как фон главного окна), а не
        // SwiftUI Material: в прозрачной безрамочной панели тот смешивается
        // только с содержимым самой панели, то есть ни с чем.
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: QuickCaptureView(
            model: model,
            viewModel: viewModel,
            onSubmit: { [weak self] in self?.submit() },
            onCancel: { [weak self] in self?.close(discardingDraft: true) }
        ))
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

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        close(discardingDraft: false)
    }
}

private struct QuickCaptureView: View {
    var model: QuickCaptureModel
    var viewModel: BoardViewModel?
    var onSubmit: () -> Void
    var onCancel: () -> Void

    var body: some View {
        let typography = viewModel?.appearanceSettings.cardTypography
            ?? AppearanceSettings.shared.cardTypography

        VStack(alignment: .leading, spacing: 10) {
            AIPromptTextView(
                text: Binding(get: { model.draft }, set: { model.draft = $0 }),
                shouldFocus: model.isPresented,
                onSend: onSubmit,
                font: typography.font,
                textColor: typography.color,
                sendKeyBinding: .returnSends,
                onEscape: onCancel
            )
            .frame(height: 96)
            .overlay(alignment: .topLeading) {
                if model.draft.isEmpty {
                    Text("Capture a thought\u{2026}")
                        .font(Font(typography.font as CTFont))
                        .foregroundStyle(Color(nsColor: typography.color).opacity(0.4))
                        .padding(.leading, 11)
                        .padding(.top, 6)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 6) {
                if viewModel?.isActiveSpaceLocked == true {
                    Image(systemName: "lock.fill")
                }
                Text("\u{2192} \(spaceName)")
                    .lineLimit(1)
                Spacer()
                Text("\u{21A9} save  \u{00B7}  \u{21E7}\u{21A9} new line  \u{00B7}  esc close")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.5))
            .padding(.horizontal, 6)
        }
        .padding(12)
        .frame(width: 480)
        // Тот же приём, что у CardSurfaceBackground: тёмный тон поверх
        // блюра — без него на светлом окне позади (Finder, Safari) панель
        // становится почти прозрачной и светлый текст теряется.
        .background(Color.black.opacity(0.35))
        .environment(\.colorScheme, .dark)
    }

    private var spaceName: String {
        guard let viewModel else { return "" }
        return viewModel.activeWorkspace?.name ?? Workspace.defaultName(forSlot: viewModel.activeSlot)
    }
}
