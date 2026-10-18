import SwiftUI
import UIKit

/// Звёзды Spoiler/Lock карточек на iPhone — одно общее поле на весь экран ленты, как на Mac:
/// карточки — «окна» в него (маска по рамкам скрытых карточек), поэтому рисунок у соседних
/// карточек разный и продолжается на стыках, а при прокрутке звёзды скользят под карточкой.
/// Системный CAEmitterLayer живёт в процессе отрисовки и не трогает главный поток; рамки
/// карточек кладутся прямо в слои маски — SwiftUI при этом не перерисовывается.
/// (Прежний StarFieldCanvas — TimelineView + Canvas на каждой карточке — давал лаги свайпов.)
/// На Mac по-прежнему StarFieldCanvas.
final class StarVoidModel {
    fileprivate weak var view: StarVoidView?
    /// nil — карточка больше не скрыта или ушла с экрана.
    func set(_ id: UUID, frame: CGRect?) { view?.setFrame(frame, for: id) }
}

struct StarEmitter: UIViewRepresentable {
    var model: StarVoidModel
    var isPaused = false

    func makeUIView(context: Context) -> StarVoidView {
        let view = StarVoidView()
        model.view = view
        return view
    }

    func updateUIView(_ view: StarVoidView, context: Context) {
        model.view = view
        view.hostPaused = isPaused
    }
}

final class StarVoidView: UIView {
    /// Мягкий край сверху и снизу — та же высота затухания, что у длинного текста.
    private static let fade: CGFloat = 15

    /// Звёзды — слои с готовыми анимациями Core Animation (мерцание и дрейф как у
    /// StarFieldCanvas на Mac): считает их сервер отрисовки, главный поток не занят.
    private let starsLayer = CALayer()
    private let maskLayer = CALayer()
    private var windows: [UUID: CAGradientLayer] = [:]
    private var frames: [UUID: CGRect] = [:] // в координатах окна
    private var builtSize = CGSize.zero
    var hostPaused = false { didSet { updatePause() } }

    private static let dot: CGImage? = {
        let size = CGSize(width: 8, height: 8)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        }.cgImage
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.addSublayer(starsLayer)
        starsLayer.mask = maskLayer
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        starsLayer.frame = bounds
        maskLayer.frame = bounds
        if bounds.size != builtSize { buildStars() }
        for (id, frame) in frames { place(id, frame) }
    }

    /// Те же звёзды и то же поле (сетка 40×40 pt, звезда клетки — по хешу), что на Mac.
    private func buildStars() {
        builtSize = bounds.size
        starsLayer.sublayers = nil
        let cell = StarFieldCanvas.cell
        let table = StarFieldCanvas.starIdentities
        let cols = Int(ceil(bounds.width / cell)), rows = Int(ceil(bounds.height / cell))
        guard cols > 0, rows > 0 else { return }
        for gx in 0..<cols {
            for gy in 0..<rows {
                let star = table[abs(((gx &* 73856093) ^ (gy &* 19349663)) % StarFieldCanvas.tableCount)]
                let dot = CALayer()
                dot.contents = Self.dot
                dot.bounds = CGRect(x: 0, y: 0, width: star.starSize, height: star.starSize)
                dot.position = CGPoint(x: (CGFloat(gx) + star.xFrac) * cell, y: (CGFloat(gy) + star.yFrac) * cell)
                // Мерцание: base ± 0.25 в пределах 0.15…0.95, период 2π / (speed · 2.5).
                let lo = max(0.15, star.baseOpacity - 0.25), hi = min(0.95, star.baseOpacity + 0.25)
                dot.opacity = Float(star.baseOpacity)
                dot.add(Self.wave("opacity", lo, hi, half: .pi / (star.speed * 2.5), phase: star.twinklePhase), forKey: "twinkle")
                // Дрейф: по y ±7, по x ±4, период 2π / (speed · 1.8) и 2π / (speed · 1.2).
                dot.add(Self.wave("transform.translation.y", -7, 7, half: .pi / (star.speed * 1.8), phase: star.xFrac * 10), forKey: "driftY")
                dot.add(Self.wave("transform.translation.x", -4, 4, half: .pi / (star.speed * 1.2), phase: star.yFrac * 10), forKey: "driftX")
                starsLayer.addSublayer(dot)
            }
        }
    }

    private static func wave(_ path: String, _ from: Double, _ to: Double, half: Double, phase: Double) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: path)
        a.fromValue = from
        a.toValue = to
        a.duration = half
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.timeOffset = phase / .pi * half // разная фаза у каждой звезды
        a.isRemovedOnCompletion = false
        return a
    }

    func setFrame(_ frame: CGRect?, for id: UUID) {
        guard let frame else {
            guard frames.removeValue(forKey: id) != nil else { return }
            windows.removeValue(forKey: id)?.removeFromSuperlayer()
            updatePause()
            return
        }
        frames[id] = frame
        place(id, frame)
        updatePause()
    }

    private func place(_ id: UUID, _ windowFrame: CGRect) {
        let rect = convert(windowFrame, from: nil)
        let window = windows[id] ?? {
            let layer = CAGradientLayer()
            layer.cornerRadius = Theme.cardRadius
            layer.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
            maskLayer.addSublayer(layer)
            windows[id] = layer
            return layer
        }()
        CATransaction.begin()
        CATransaction.setDisableActions(true) // рамка едет за пальцем без неявных анимаций
        window.frame = rect
        let f = min(Self.fade / max(rect.height, 1), 0.5)
        window.locations = [0, f, 1 - f, 1].map { NSNumber(value: $0) }
        CATransaction.commit()
    }

    /// Пауза — слой замирает целиком (скрытых карточек нет / не текущий Space).
    private func updatePause() {
        let paused = hostPaused || frames.isEmpty
        starsLayer.isHidden = frames.isEmpty
        let layer = starsLayer
        guard (layer.speed == 0) != paused else { return }
        if paused {
            layer.timeOffset = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
        } else {
            let paused = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - paused
        }
    }
}
