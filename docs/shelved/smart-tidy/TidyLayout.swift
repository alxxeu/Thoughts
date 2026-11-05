import CoreGraphics
import Foundation

/// Tidy Cards — чистая раскладка без AI и без BoardViewModel (чтобы её можно
/// было тестировать): группы → выравнивание размеров в группе → блоки →
/// размещение. Крупные блоки уходят в углы канвы, мелкие — к центру; если
/// группа одна (или карточек очень мало), всё складывается одним блоком по
/// центру. Результат детерминирован и не зависит от порядка входа, поэтому
/// повторный Tidy на уже разложенном поле ничего не двигает.
enum TidyLayout {
    struct Item {
        let id: UUID
        var origin: CGPoint
        var size: CGSize
        let tag: String?
        /// Меньше этого размера карточку при выравнивании не сжимаем.
        let minSize: CGSize
    }

    struct Placement: Equatable {
        var origin: CGPoint
        var size: CGSize
    }

    private static var gap: CGFloat { BoardViewModel.cardGap }
    private static var step: CGFloat { BoardViewModel.cardSizeStep }
    /// Карточки ближе этого друг к другу (после зазора) считаются одной группой.
    private static var linkDistance: CGFloat { gap + 8 }
    /// Зазор между блоками заметно больше зазора между карточками и больше
    /// linkDistance — иначе при втором Tidy соседние блоки слиплись бы в одну группу.
    private static var blockGap: CGFloat { 3 * gap }

    // MARK: - Вход

    /// nil — раскладывать нечего или всё и так на месте (сдвиги меньше gap/2, размеры те же).
    /// `forcedGroups` — готовые группы (от модели): карточки в них идут в заданном порядке;
    /// не попавшие ни в одну группу (spoiler/lock, пропущенные моделью) добавляются к группе
    /// с тем же тегом или группируются как обычно.
    static func plan(_ items: [Item], canvas: CGSize, topInset: CGFloat, forcedGroups: [[UUID]]? = nil) -> [UUID: Placement]? {
        guard !items.isEmpty else { return nil }
        let pad = BoardViewModel.canvasSidePadding
        let area = CGRect(x: pad, y: topInset, width: max(0, canvas.width - 2 * pad), height: max(0, canvas.height - pad - topInset))

        // 1–2 карточки: группировка бессмысленна, одна группа по центру.
        var groups: [(items: [Item], keepOrder: Bool)]
        if items.count <= 2 {
            groups = [(items, false)]
        } else if let forcedGroups {
            groups = mergeForced(forcedGroups, into: items)
        } else {
            groups = mergeSingles(makeGroups(items)).map { ($0, false) }
        }

        // Мало карточек (группы случайны) или углы с островом не поместились — одна
        // ровная сетка: группы идут подряд, крупные первыми.
        let fill = items.reduce(CGFloat(0)) { $0 + $1.size.width * $1.size.height } / max(1, area.width * area.height)
        let flat: [(items: [Item], keepOrder: Bool)] = [(groups.sorted { ($0.items.count, $1.items.first?.id.uuidString ?? "") > ($1.items.count, $0.items.first?.id.uuidString ?? "") }.flatMap(\.items), true)]
        let useGrid = groups.count < 2 || fill < 0.15
        let result = (useGrid ? nil : layout(groups, area: area, strict: true))
            ?? layout(flat, area: area, strict: true)
            // shortcut: карточки не помещаются в канву даже сеткой — наложения неизбежны; когда понадобится, сжимать.
            ?? layout(flat, area: area, strict: false)!

        let unchanged = items.allSatisfy { item in
            guard let new = result[item.id] else { return true }
            return new.size == item.size
                && abs(new.origin.x - item.origin.x) < gap / 2
                && abs(new.origin.y - item.origin.y) < gap / 2
        }
        return unchanged ? nil : result
    }

    private static func layout(_ groups: [(items: [Item], keepOrder: Bool)], area: CGRect, strict: Bool) -> [UUID: Placement]? {
        let blocks = groups.map { makeBlock($0.items, area: area, halfSized: groups.count > 1, keepOrder: $0.keepOrder) }
        guard let origins = place(blocks, area: area, strict: strict) else { return nil }
        var result: [UUID: Placement] = [:]
        for (block, origin) in zip(blocks, origins) {
            for (id, rect) in block.rects {
                result[id] = Placement(origin: CGPoint(x: origin.x + rect.minX, y: origin.y + rect.minY), size: rect.size)
            }
        }
        return result
    }

    // MARK: - Группы

    private static func mergeForced(_ forced: [[UUID]], into items: [Item]) -> [(items: [Item], keepOrder: Bool)] {
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var used = Set<UUID>()
        var groups: [[Item]] = forced.map { ids in
            ids.compactMap { id in
                guard let item = byId[id], used.insert(id).inserted else { return nil }
                return item
            }
        }.filter { !$0.isEmpty }
        var rest: [Item] = []
        for item in items.sorted(by: readingOrder) where !used.contains(item.id) {
            if let tag = item.tag, let index = groups.firstIndex(where: { $0.contains { $0.tag == tag } }) {
                groups[index].append(item)
            } else {
                rest.append(item)
            }
        }
        return groups.map { ($0, true) } + mergeSingles(makeGroups(rest)).map { ($0, false) }
    }

    /// Одинаковый тег (если карточек 2+) — одна группа. Остальные —
    /// кластеры по близости (single-link): карточки, лежащие рядом,
    /// остаются вместе.
    static func makeGroups(_ items: [Item]) -> [[Item]] {
        let sorted = items.sorted(by: readingOrder)
        let tagged = Dictionary(grouping: sorted.filter { $0.tag != nil }) { $0.tag! }
        var groups: [[Item]] = []
        var loose: [Item] = []
        for tag in tagged.keys.sorted() {
            let members = tagged[tag]!
            if members.count > 1 { groups.append(members) } else { loose += members }
        }
        loose = (loose + sorted.filter { $0.tag == nil }).sorted(by: readingOrder)

        // Обход в ширину по связям «ближе linkDistance».
        var visited = Set<UUID>()
        for seed in loose where !visited.contains(seed.id) {
            var cluster: [Item] = []
            var queue = [seed]
            visited.insert(seed.id)
            while let current = queue.popLast() {
                cluster.append(current)
                for other in loose where !visited.contains(other.id) && isNear(current, other) {
                    visited.insert(other.id)
                    queue.append(other)
                }
            }
            groups.append(cluster.sorted(by: readingOrder))
        }
        return groups
    }

    /// Одиночные карточки (группы из одной) собираются в один общий блок,
    /// чтобы они не разбегались по полю.
    private static func mergeSingles(_ groups: [[Item]]) -> [[Item]] {
        let singles = groups.filter { $0.count == 1 }.flatMap { $0 }
        guard singles.count > 1 else { return groups }
        return groups.filter { $0.count > 1 } + [singles.sorted(by: readingOrder)]
    }

    private static func isNear(_ a: Item, _ b: Item) -> Bool {
        let ra = CGRect(origin: a.origin, size: a.size).insetBy(dx: -linkDistance / 2, dy: -linkDistance / 2)
        let rb = CGRect(origin: b.origin, size: b.size).insetBy(dx: -linkDistance / 2, dy: -linkDistance / 2)
        return ra.intersects(rb)
    }

    /// Сверху вниз, слева направо; id — чтобы порядок был полностью детерминирован.
    private static func readingOrder(_ a: Item, _ b: Item) -> Bool {
        if a.origin.y != b.origin.y { return a.origin.y < b.origin.y }
        if a.origin.x != b.origin.x { return a.origin.x < b.origin.x }
        return a.id.uuidString < b.id.uuidString
    }

    // MARK: - Размеры

    private static func tiles(_ value: CGFloat) -> Int { max(2, Int(((value + gap) / step).rounded())) }
    private static func length(_ tiles: Int) -> CGFloat { CGFloat(tiles) * step - gap }

    /// Подгоняет размеры карточек группы так, чтобы блок вышел ровным
    /// (каждая ось отдельно, всё на сетке плиток):
    /// — если у ≥2/3 группы (от 3 карточек) один размер, остальные берут его;
    /// — иначе 1–2 карточки, отличающиеся на плитку, подтягиваются к самому
    ///   частому размеру, но только в большую сторону (текст не режем).
    static func normalizedSizes(_ group: [Item]) -> [UUID: CGSize] {
        // Все размеры — на сетку плиток: почти одинаковые карточки становятся одинаковыми.
        var sizes = Dictionary(uniqueKeysWithValues: group.map { ($0.id, CGSize(width: length(tiles($0.size.width)), height: length(tiles($0.size.height)))) })
        guard group.count >= 3 else { return sizes }
        for axis in [Axis.width, .height] {
            let counts = group.reduce(into: [Int: Int]()) { $0[tiles(axis.value($1.size)), default: 0] += 1 }
            // Самый частый размер; при ничьей — меньший (стабильно).
            guard let mode = counts.max(by: { ($0.value, -$0.key) < ($1.value, -$1.key) }) else { continue }
            let strong = mode.value * 3 >= group.count * 2
            let outliers = group.filter { tiles(axis.value($0.size)) != mode.key }
            let nearOutliers = outliers.filter { abs(tiles(axis.value($0.size)) - mode.key) == 1 }
            let adaptAll = strong
            let adaptNear = !strong && outliers.count <= 2 && nearOutliers.count == outliers.count
            guard adaptAll || adaptNear else { continue }
            let target = length(mode.key)
            for card in outliers {
                let grows = target > axis.value(sizes[card.id]!)
                // shortcut: сжимаем по minSize, а не по реальному тексту, — когда измерим текст, учесть его здесь.
                guard grows || (adaptAll && target >= axis.value(card.minSize)) else { continue }
                sizes[card.id] = axis.set(sizes[card.id]!, target)
            }
        }
        return sizes
    }

    private enum Axis {
        case width, height
        func value(_ s: CGSize) -> CGFloat { self == .width ? s.width : s.height }
        func set(_ s: CGSize, _ v: CGFloat) -> CGSize { self == .width ? CGSize(width: v, height: s.height) : CGSize(width: s.width, height: v) }
    }

    // MARK: - Блоки

    struct Block {
        /// Прямоугольники карточек в системе координат блока (0,0 — левый верхний угол).
        var rects: [UUID: CGRect]
        var size: CGSize
        /// Центр прежних позиций карточек — к нему блок тянется при размещении.
        var previousCenter: CGPoint
        var tieBreak: String
    }

    static func makeBlock(_ group: [Item], area: CGRect, halfSized: Bool, keepOrder: Bool = false) -> Block {
        let sizes = normalizedSizes(group)
        // Внутри группы: по тегу, затем по порядку чтения (после Tidy он тот же — стабильно).
        let ordered = keepOrder ? group : group.sorted(by: readingOrder)
        let widths = ordered.map { sizes[$0.id]!.width }
        let heights = ordered.map { sizes[$0.id]!.height }
        let maxW = halfSized ? area.width / 2 : area.width
        let maxH = halfSized ? area.height / 2 : area.height
        let layout = bestShelf(widths: widths, heights: heights, maxWidth: maxW, maxHeight: maxH)
        var rects: [UUID: CGRect] = [:]
        for (index, item) in ordered.enumerated() {
            rects[item.id] = CGRect(origin: layout.origins[index], size: CGSize(width: widths[index], height: heights[index]))
        }
        let centers = group.map { CGPoint(x: $0.origin.x + $0.size.width / 2, y: $0.origin.y + $0.size.height / 2) }
        let center = CGPoint(x: centers.map(\.x).reduce(0, +) / CGFloat(centers.count), y: centers.map(\.y).reduce(0, +) / CGFloat(centers.count))
        return Block(rects: rects, size: layout.size, previousCenter: center, tieBreak: group.map { $0.id.uuidString }.min() ?? "")
    }

    private struct Shelf { var origins: [CGPoint]; var size: CGSize }

    /// Построчная упаковка с заданной шириной ряда.
    private static func shelf(widths: [CGFloat], heights: [CGFloat], rowWidth: CGFloat, spacing: CGFloat = gap) -> Shelf {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for (w, h) in zip(widths, heights) {
            if x > 0, x + w > rowWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += w + spacing
            rowHeight = max(rowHeight, h)
            usedWidth = max(usedWidth, x - spacing)
        }
        return Shelf(origins: origins, size: CGSize(width: usedWidth, height: y + rowHeight))
    }

    /// Все различимые варианты ширины ряда (кумулятивные ширины), от самого
    /// «квадратного»: меньше большая сторона, затем меньше площадь, затем шире,
    /// чем выше. Без этого минимум площади даёт длинный ряд или колонку.
    private static func shelfCandidates(widths: [CGFloat], heights: [CGFloat], maxWidth: CGFloat, spacing: CGFloat = gap) -> [Shelf] {
        var candidates = Set<CGFloat>([maxWidth])
        var cumulative: CGFloat = -spacing
        for w in widths {
            cumulative += w + spacing
            candidates.insert(min(cumulative, maxWidth))
        }
        func cost(_ s: Shelf) -> [CGFloat] { [max(s.size.width, s.size.height), s.size.width * s.size.height, -s.size.width] }
        return candidates.sorted()
            .map { shelf(widths: widths, heights: heights, rowWidth: $0, spacing: spacing) }
            .filter { $0.size.width <= maxWidth + 0.5 }
            .sorted { cost($0).lexicographicallyPrecedes(cost($1)) }
    }

    private static func bestShelf(widths: [CGFloat], heights: [CGFloat], maxWidth: CGFloat, maxHeight: CGFloat) -> Shelf {
        // shortcut: ничего не влезло в свою половину канвы — берём во всю ширину, блок может выйти за неё; когда понадобится, сжимать группу.
        shelfCandidates(widths: widths, heights: heights, maxWidth: maxWidth).first { $0.size.height <= maxHeight }
            ?? shelf(widths: widths, heights: heights, rowWidth: maxWidth)
    }

    // MARK: - Размещение

    /// Возвращает левый верхний угол каждого блока (в порядке `blocks`).
    /// Крупные блоки — в углы; все остальные — одним «островом» по центру
    /// (ряды блоков, крупные первыми). Если остров не помещается между углами,
    /// все блоки идут рядами по центру канвы.
    static func place(_ blocks: [Block], area: CGRect, strict: Bool = false) -> [CGPoint]? {
        var origins = [CGPoint](repeating: area.origin, count: blocks.count)
        var placed: [CGRect] = []
        let center = CGPoint(x: area.midX, y: area.midY)

        func clamp(_ o: CGPoint, _ s: CGSize) -> CGPoint {
            CGPoint(x: min(max(o.x, area.minX), max(area.minX, area.maxX - s.width)),
                    y: min(max(o.y, area.minY), max(area.minY, area.maxY - s.height)))
        }
        /// Ближайшее к `ideal` свободное место: сетка с шагом step/2.
        func spot(_ s: CGSize, around ideal: CGPoint, margin: CGFloat) -> CGPoint? {
            var best: (CGPoint, CGFloat)?
            var y = area.minY
            while y + s.height <= area.maxY + 0.5 {
                var x = area.minX
                while x + s.width <= area.maxX + 0.5 {
                    let rect = CGRect(origin: CGPoint(x: x, y: y), size: s)
                    if !placed.contains(where: { $0.insetBy(dx: -margin, dy: -margin).intersects(rect) }) {
                        let d = hypot(x - ideal.x, y - ideal.y)
                        if best == nil || d < best!.1 { best = (CGPoint(x: x, y: y), d) }
                    }
                    x += step / 2
                }
                y += step / 2
            }
            return best?.0
        }
        /// Блоки `indices` рядами одним островом у центра; false — не поместился.
        func placeIsland(_ indices: [Int]) -> Bool {
            guard !indices.isEmpty else { return true }
            let layouts = shelfCandidates(widths: indices.map { blocks[$0].size.width }, heights: indices.map { blocks[$0].size.height },
                                          maxWidth: area.width, spacing: blockGap)
            for layout in layouts where layout.size.height <= area.height {
                let ideal = clamp(CGPoint(x: center.x - layout.size.width / 2, y: center.y - layout.size.height / 2), layout.size)
                guard let o = spot(layout.size, around: ideal, margin: blockGap) ?? spot(layout.size, around: ideal, margin: gap) else { continue }
                for (k, index) in indices.enumerated() {
                    origins[index] = CGPoint(x: o.x + layout.origins[k].x, y: o.y + layout.origins[k].y)
                    placed.append(CGRect(origin: origins[index], size: blocks[index].size))
                }
                return true
            }
            return false
        }

        // Крупные первыми; при равенстве — по id, не по положению.
        let order = blocks.indices.sorted {
            let a = blocks[$0], b = blocks[$1]
            let aa = a.size.width * a.size.height, ba = b.size.width * b.size.height
            return aa != ba ? aa > ba : a.tieBreak < b.tieBreak
        }
        let totalArea = blocks.reduce(CGFloat(0)) { $0 + $1.size.width * $1.size.height }
        let isSmall = totalArea < area.width * area.height * 0.15

        if blocks.count >= 2, !isSmall {
            // В угол — только крупные блоки (от трети самого крупного).
            let maxArea = blocks[order[0]].size.width * blocks[order[0]].size.height
            var freeCorners: [Corner] = Corner.allCases
            var rest: [Int] = []
            for i in order {
                let block = blocks[i]
                guard !freeCorners.isEmpty, block.size.width * block.size.height * 3 >= maxArea else { rest.append(i); continue }
                // Угол, ближайший к прежнему положению блока.
                let corner = freeCorners.min {
                    hypot(block.previousCenter.x - $0.anchor(area).x, block.previousCenter.y - $0.anchor(area).y)
                        < hypot(block.previousCenter.x - $1.anchor(area).x, block.previousCenter.y - $1.anchor(area).y)
                }!
                freeCorners.removeAll { $0 == corner }
                origins[i] = corner.origin(for: block.size, in: area)
                placed.append(CGRect(origin: origins[i], size: block.size))
            }
            if placeIsland(rest) { return origins }
            placed = []
        }
        // Мало карточек, один блок или остров не влез: все блоки рядами по центру.
        if !placeIsland(order) {
            if strict { return nil }
            // shortcut: места нет совсем — блоки встанут рядами у центра с наложением; когда понадобится, сжимать группы.
            if let layout = shelfCandidates(widths: order.map { blocks[$0].size.width }, heights: order.map { blocks[$0].size.height }, maxWidth: area.width, spacing: gap).first {
                let o = clamp(CGPoint(x: center.x - layout.size.width / 2, y: center.y - layout.size.height / 2), layout.size)
                for (k, index) in order.enumerated() { origins[index] = CGPoint(x: o.x + layout.origins[k].x, y: o.y + layout.origins[k].y) }
            }
        }
        return origins
    }

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        func anchor(_ a: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: a.minX, y: a.minY)
            case .topRight: return CGPoint(x: a.maxX, y: a.minY)
            case .bottomLeft: return CGPoint(x: a.minX, y: a.maxY)
            case .bottomRight: return CGPoint(x: a.maxX, y: a.maxY)
            }
        }
        func origin(for s: CGSize, in a: CGRect) -> CGPoint {
            let p = anchor(a)
            switch self {
            case .topLeft: return p
            case .topRight: return CGPoint(x: p.x - s.width, y: p.y)
            case .bottomLeft: return CGPoint(x: p.x, y: p.y - s.height)
            case .bottomRight: return CGPoint(x: p.x - s.width, y: p.y - s.height)
            }
        }
    }
}
