import SwiftUI
import UIKit

/// Звёзды Spoiler/Lock карточки на iPhone — системный CAEmitterLayer: частицы живут
/// в процессе отрисовки и не трогают главный поток. Прежний StarFieldCanvas
/// (TimelineView + Canvas, 24 кадра/сек) на каждой видимой карточке заново
/// пересчитывал граф SwiftUI — на айфоне это и давало лаги свайпов и клавиатуры.
/// На Mac по-прежнему StarFieldCanvas.
struct StarEmitter: UIViewRepresentable {
    var isPaused = false

    func makeUIView(context: Context) -> StarEmitterView { StarEmitterView() }

    func updateUIView(_ view: StarEmitterView, context: Context) {
        view.setPaused(isPaused)
    }
}

final class StarEmitterView: UIView {
    override class var layerClass: AnyClass { CAEmitterLayer.self }
    private var emitter: CAEmitterLayer { layer as! CAEmitterLayer }
    private static let lifetime: Float = 7
    /// 1 звезда на ~1600 pt² (как в StarFieldCanvas), не больше 300.
    private static let density: CGFloat = 1 / 1600

    private static let dot: CGImage? = {
        let size = CGSize(width: 6, height: 6)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        }.cgImage
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        emitter.emitterShape = .rectangle

        let cell = CAEmitterCell()
        cell.contents = Self.dot
        cell.lifetime = Self.lifetime
        cell.lifetimeRange = 3
        cell.velocity = 3
        cell.velocityRange = 3
        cell.emissionRange = .pi * 2
        cell.scale = 0.17
        cell.scaleRange = 0.07
        // Появляются мелкими и растут, гаснут к концу жизни — без резкого «щёлк».
        cell.scaleSpeed = 0.012
        cell.alphaRange = 0.25
        cell.color = UIColor(white: 1, alpha: 0.7).cgColor
        cell.alphaSpeed = -0.7 / Self.lifetime
        emitter.emitterCells = [cell]
        // Прогрев: звёзды есть сразу, а не набираются несколько секунд.
        emitter.beginTime = CACurrentMediaTime() - Double(Self.lifetime)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        emitter.emitterSize = bounds.size
        let count = min(300, max(6, bounds.width * bounds.height * Self.density))
        emitter.emitterCells?.first?.birthRate = Float(count) / Self.lifetime
    }

    /// Пауза — слой замирает целиком (карточка не на экране / не текущий Space).
    func setPaused(_ paused: Bool) {
        let layer = emitter
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
