import AppKit
import CoreImage
import ScreenCaptureKit
import SwiftUI

/// Фон окна без живого блюра (BACKLOG «прямоугольные швы»): разовый снимок
/// окна обоев через ScreenCaptureKit, размытый Core Image, — дальше это
/// обычная картинка, WindowServer её не пересчитывает, швов нет.
///
/// Нужно разрешение Screen Recording. Снимается только слой обоев (окна
/// уровня рабочего стола), без иконок и чужих окон. Переснимаем при смене
/// Space, мониторов, возврате в приложение и раз в несколько минут.
@Observable
final class WallpaperSnapshot {
    static let shared = WallpaperSnapshot()

    /// Размытые обои по дисплеям (CGDirectDisplayID).
    private(set) var images: [CGDirectDisplayID: CGImage] = [:]
    /// Разрешения нет — рисуем запасной фон.
    private(set) var isDenied = false

    private var isRunning = false
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var captureTask: Task<Void, Never>?

    private init() {}

    /// Включить снимки (идемпотентно). Без разрешения один раз просит его.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        if !CGPreflightScreenCaptureAccess() {
            isDenied = !CGRequestScreenCaptureAccess()
            if isDenied { return }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        })
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didChangeScreenParametersNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers = []
        timer?.invalidate()
        timer = nil
        captureTask?.cancel()
        images = [:]
    }

    func refresh() {
        guard isRunning else { return }
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            // Переход между Spaces ещё анимируется — снимаем уже готовые обои.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            do {
                let captured = try await Self.captureWallpapers()
                guard !Task.isCancelled else { return }
                images = captured
                isDenied = false
            } catch {
                isDenied = !CGPreflightScreenCaptureAccess()
            }
        }
    }

    private static let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))

    private static func captureWallpapers() async throws -> [CGDirectDisplayID: CGImage] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var result: [CGDirectDisplayID: CGImage] = [:]
        for display in content.displays {
            // Слой обоев — окна уровня рабочего стола на этом дисплее (на
            // macOS 14+ их держит WallpaperAgent, раньше — Dock). Иконки
            // Finder лежат выше и сюда не попадают.
            let wallpaperWindows = content.windows.filter {
                $0.windowLayer <= desktopLevel && $0.frame.intersects(display.frame)
            }
            guard !wallpaperWindows.isEmpty else { continue }

            let filter = SCContentFilter(display: display, including: wallpaperWindows)
            let config = SCStreamConfiguration()
            // Всё равно размываем — полного разрешения не нужно.
            config.width = max(display.width / 2, 1)
            config.height = max(display.height / 2, 1)
            config.showsCursor = false

            let shot = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            if let blurred = await blur(shot) {
                result[display.displayID] = blurred
            }
        }
        return result
    }

    /// CIContext потокобезопасен — общий для фоновых задач размытия.
    nonisolated(unsafe) private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private static func blur(_ image: CGImage) async -> CGImage? {
        await Task.detached(priority: .utility) { () -> CGImage? in
            let input = CIImage(cgImage: image)
            let blurred = input
                .clampedToExtent()
                .applyingGaussianBlur(sigma: 30)
                .cropped(to: input.extent)
            return ciContext.createCGImage(blurred, from: input.extent)
        }.value
    }
}

/// Кусок снимка обоев ровно под окном: картинка своего экрана растянута на
/// весь экран, а показывается её часть по текущей рамке окна (обновляется
/// при движении окна и переходе на другой монитор).
struct WallpaperBackdropView: NSViewRepresentable {
    var images: [CGDirectDisplayID: CGImage]

    func makeNSView(context: Context) -> BackdropNSView { BackdropNSView() }

    func updateNSView(_ nsView: BackdropNSView, context: Context) {
        nsView.images = images
    }

    final class BackdropNSView: NSView {
        var images: [CGDirectDisplayID: CGImage] = [:] {
            didSet { needsDisplay = true }
        }
        private var observers: [NSObjectProtocol] = []

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.contentsGravity = .resize
        }

        required init?(coder: NSCoder) { fatalError() }

        override var wantsUpdateLayer: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = []
            guard let window else { return }
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.needsDisplay = true
                })
            }
            needsDisplay = true
        }

        override func layout() {
            super.layout()
            needsDisplay = true
        }

        override func updateLayer() {
            guard let layer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            guard let window, let screen = window.screen,
                  let id = screen.displayID, let image = images[id] else {
                layer.contents = nil
                return
            }
            layer.contents = image
            // Рамка этого вида в координатах экрана → доля картинки (у CALayer
            // на macOS начало contentsRect — снизу слева, как у экрана).
            let rectInScreen = window.convertToScreen(convert(bounds, to: nil))
            let s = screen.frame
            layer.contentsRect = CGRect(
                x: (rectInScreen.minX - s.minX) / s.width,
                y: (rectInScreen.minY - s.minY) / s.height,
                width: rectInScreen.width / s.width,
                height: rectInScreen.height / s.height
            )
        }

        deinit {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

/// Фон окна из снимка обоев; пока снимка нет или нет разрешения — запасной
/// Ultra Thin Material.
struct WallpaperSnapshotBackground: View {
    private let snapshot = WallpaperSnapshot.shared

    var body: some View {
        ZStack {
            if snapshot.images.isEmpty {
                Rectangle().fill(.ultraThinMaterial)
            } else {
                WallpaperBackdropView(images: snapshot.images)
                // Лёгкая подложка окна поверх — как тонировка материала.
                Color(nsColor: .windowBackgroundColor).opacity(0.25)
            }
        }
        .onAppear { snapshot.start() }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
