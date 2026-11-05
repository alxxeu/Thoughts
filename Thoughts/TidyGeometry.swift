import CoreGraphics
import Foundation

/// Tidy Cards: «донастройка» размеров карточек одного угла, чтобы они складывались в ровный
/// прямоугольник. Всё на сетке плиток `size(k) = k*cardSizeStep − cardGap`, ось за осью:
/// — все размеры округляются до сетки (почти одинаковые карточки становятся одинаковыми);
/// — если у ≥2/3 группы (от 3 карточек) один размер, остальные берут его;
/// — иначе 1–2 карточки, отличающиеся на плитку, подтягиваются к самому частому размеру,
///   но только в большую сторону.
enum TidyGeometry {
    struct Item {
        let id: UUID
        var size: CGSize
    }

    private static var gap: CGFloat { BoardViewModel.cardGap }
    private static var step: CGFloat { BoardViewModel.cardSizeStep }
    private static func tiles(_ value: CGFloat) -> Int { max(2, Int(((value + gap) / step).rounded())) }
    private static func length(_ tiles: Int) -> CGFloat { CGFloat(tiles) * step - gap }

    static func normalizedSizes(_ group: [Item]) -> [UUID: CGSize] {
        var sizes = Dictionary(uniqueKeysWithValues: group.map {
            ($0.id, CGSize(width: length(tiles($0.size.width)), height: length(tiles($0.size.height))))
        })
        guard group.count >= 3 else { return sizes }
        for axis in [Axis.width, .height] {
            let counts = group.reduce(into: [Int: Int]()) { $0[tiles(axis.value($1.size)), default: 0] += 1 }
            // Самый частый размер; при ничьей — меньший (стабильно).
            guard let mode = counts.max(by: { ($0.value, -$0.key) < ($1.value, -$1.key) }) else { continue }
            let strong = mode.value * 3 >= group.count * 2
            let outliers = group.filter { tiles(axis.value($0.size)) != mode.key }
            let nearOutliers = outliers.filter { abs(tiles(axis.value($0.size)) - mode.key) == 1 }
            let adaptNear = !strong && outliers.count <= 2 && nearOutliers.count == outliers.count
            guard strong || adaptNear else { continue }
            let target = length(mode.key)
            for item in outliers {
                let current = axis.value(sizes[item.id]!)
                // shortcut: сжимаем по минимальному размеру карточки, а не по реальному тексту.
                guard target > current || (strong && target >= BoardViewModel.minCardSize) else { continue }
                sizes[item.id] = axis.set(sizes[item.id]!, target)
            }
        }
        return sizes
    }

    private enum Axis {
        case width, height
        func value(_ s: CGSize) -> CGFloat { self == .width ? s.width : s.height }
        func set(_ s: CGSize, _ v: CGFloat) -> CGSize { self == .width ? CGSize(width: v, height: s.height) : CGSize(width: s.width, height: v) }
    }
}
