import CoreGraphics
import Foundation
import Testing
@testable import Thoughts

struct TidyLayoutTests {
    private let canvas = CGSize(width: 1200, height: 800)
    private let top: CGFloat = 40
    private let small = BoardViewModel.minCardSize // 104

    private func item(_ x: CGFloat, _ y: CGFloat, w: CGFloat? = nil, h: CGFloat? = nil, tag: String? = nil) -> TidyLayout.Item {
        TidyLayout.Item(id: UUID(), origin: CGPoint(x: x, y: y), size: CGSize(width: w ?? small, height: h ?? small), tag: tag,
                        minSize: CGSize(width: small, height: small))
    }

    private func rect(_ id: UUID, _ plan: [UUID: TidyLayout.Placement]) -> CGRect {
        CGRect(origin: plan[id]!.origin, size: plan[id]!.size)
    }

    /// Применяет план и возвращает новые items — для проверки повторного Tidy.
    private func applied(_ items: [TidyLayout.Item], _ plan: [UUID: TidyLayout.Placement]) -> [TidyLayout.Item] {
        items.map { var i = $0; if let p = plan[i.id] { i.origin = p.origin; i.size = p.size }; return i }
    }

    @Test func emptyAndSingleCard() throws {
        #expect(TidyLayout.plan([], canvas: canvas, topInset: top) == nil)
        let one = item(10, 500)
        let plan = try #require(TidyLayout.plan([one], canvas: canvas, topInset: top))
        let r = rect(one.id, plan)
        #expect(abs(r.midX - canvas.width / 2) < 40 && abs(r.midY - (top + canvas.height) / 2) < 40)
    }

    @Test func twoFarCardsStayOneCenteredGroup() throws {
        let a = item(30, 60), b = item(1000, 650)
        let plan = try #require(TidyLayout.plan([a, b], canvas: canvas, topInset: top))
        let ra = rect(a.id, plan), rb = rect(b.id, plan)
        #expect(abs(ra.midY - rb.midY) < 1 || abs(ra.midX - rb.midX) < 1 || ra.union(rb).width < 400)
        #expect(!ra.intersects(rb))
        #expect(abs(ra.union(rb).midX - canvas.width / 2) < 60)
    }

    @Test func singleBigGroupGoesToCenter() throws {
        // Все карточки лежат рядом — одна группа, блок по центру, а не в углу.
        let items = (0..<6).map { item(30 + CGFloat($0) * 120, 60) }
        let plan = try #require(TidyLayout.plan(items, canvas: canvas, topInset: top))
        let union = items.map { rect($0.id, plan) }.reduce(CGRect.null) { $0.union($1) }
        #expect(abs(union.midX - canvas.width / 2) < 60)
        #expect(abs(union.midY - (top + canvas.height) / 2) < 80)
    }

    @Test func bigGroupsGoToCornersSmallOneToCenter() throws {
        func cluster(_ ox: CGFloat, _ oy: CGFloat, count: Int, tag: String) -> [TidyLayout.Item] {
            (0..<count).map { item(ox + CGFloat($0 % 4) * 120, oy + CGFloat($0 / 4) * 120, tag: tag) }
        }
        let tl = cluster(30, 50, count: 8, tag: "red")
        let br = cluster(700, 560, count: 8, tag: "blue")
        let mid = cluster(500, 350, count: 2, tag: "green")
        let items = tl + br + mid
        let plan = try #require(TidyLayout.plan(items, canvas: canvas, topInset: top))
        let bounds = { (g: [TidyLayout.Item]) in g.map { rect($0.id, plan) }.reduce(CGRect.null) { $0.union($1) } }
        let bTL = bounds(tl), bBR = bounds(br), bMid = bounds(mid)
        #expect(bTL.minX < 40 && bTL.minY < top + 10)
        #expect(bBR.maxX > canvas.width - 40 && bBR.maxY > canvas.height - 40)
        #expect(abs(bMid.midX - canvas.width / 2) < 200)
        #expect(!bMid.intersects(bTL) && !bMid.intersects(bBR))
    }

    @Test func noOverlapsAndInsideCanvas() throws {
        var items: [TidyLayout.Item] = []
        for i in 0..<20 {
            items.append(item(CGFloat(i * 53 % 1000) + 24, CGFloat(i * 97 % 600) + 50,
                              w: i % 3 == 0 ? 164 : small, tag: i % 4 == 0 ? "red" : nil))
        }
        let plan = try #require(TidyLayout.plan(items, canvas: canvas, topInset: top))
        let rects = items.map { rect($0.id, plan) }
        let bounds = CGRect(x: 0, y: top, width: canvas.width, height: canvas.height - top)
        for (i, r) in rects.enumerated() {
            #expect(bounds.contains(r))
            for other in rects[(i + 1)...] { #expect(!r.intersects(other), "\(r) \(other) groups \(TidyLayout.makeGroups(items).map(\.count))") }
        }
    }

    @Test func sameTagIsOneGroup() {
        let items = [item(30, 60, tag: "red"), item(900, 600, tag: "red"), item(500, 300, tag: "blue"), item(520, 700, tag: "blue")]
        let groups = TidyLayout.makeGroups(items)
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { Set($0.compactMap(\.tag)).count == 1 })
    }

    @Test func nearbyUntaggedCardsStayTogether() {
        let items = [item(30, 60), item(150, 60), item(900, 600)]
        #expect(TidyLayout.makeGroups(items).map(\.count).sorted() == [1, 2])
    }

    @Test func majoritySizeIsAdoptedByEveryone() {
        // 4 из 5 — минимальный квадрат: пятая (большая) подстраивается.
        let big = item(0, 0, w: 224, h: 164)
        let group = [item(0, 0), item(0, 0), item(0, 0), item(0, 0), big]
        let sizes = TidyLayout.normalizedSizes(group)
        #expect(sizes.values.allSatisfy { $0 == CGSize(width: small, height: small) })
    }

    @Test func nearOutlierGrowsToWeakMode() {
        // Разнобой без явного большинства, но одна карточка уже на плитку — дотягивается вверх.
        let wide = BoardViewModel.snap(164)
        let group = [item(0, 0, w: wide), item(0, 0, w: wide), item(0, 0, w: small), item(0, 0, w: small + 60)]
        let sizes = TidyLayout.normalizedSizes(group)
        #expect(sizes[group[2].id]?.width == wide)
    }

    @Test func oddOnesInMixedGroupAreLeftAlone() {
        // Два размера поровну и сильно разные — это намеренно, не трогаем.
        let group = [item(0, 0), item(0, 0), item(0, 0, w: 344, h: 344), item(0, 0, w: 344, h: 344)]
        #expect(TidyLayout.normalizedSizes(group) == Dictionary(uniqueKeysWithValues: group.map { ($0.id, $0.size) }))
    }

    @Test func secondTidyMovesNothing() throws {
        var items: [TidyLayout.Item] = []
        for i in 0..<14 {
            let x = CGFloat(i * 131 % 1000) + 24
            let y = CGFloat(i * 77 % 600) + 50
            let tags: [String?] = ["red", "blue", nil]
            items.append(item(x, y, tag: tags[i % 3]))
        }
        let plan = try #require(TidyLayout.plan(items, canvas: canvas, topInset: top))
        #expect(TidyLayout.plan(applied(items, plan), canvas: canvas, topInset: top) == nil)
    }

    @Test func orderOfInputDoesNotMatter() throws {
        let items: [TidyLayout.Item] = (0..<8).map { i in
            let x = CGFloat(i * 140 % 900) + 30
            let y = CGFloat(i * 90 % 500) + 60
            return item(x, y, tag: i % 2 == 0 ? "red" : "blue")
        }
        let a = try #require(TidyLayout.plan(items, canvas: canvas, topInset: top))
        let b = try #require(TidyLayout.plan(items.reversed(), canvas: canvas, topInset: top))
        #expect(a == b)
    }

    @Test func forcedGroupsStayTogetherAndKeepOrder() throws {
        // Две группы от модели, карточки перемешаны по полю; приватная (без группы) остаётся на месте группировки по близости.
        let a = (0..<4).map { item(CGFloat($0) * 250 + 30, 100, w: 164, h: 164) }
        let b = (0..<4).map { item(CGFloat($0) * 250 + 140, 500, w: 164, h: 164) }
        let groups = [[a[0], b[0], a[1], b[1]].map(\.id), [a[2], b[2], a[3], b[3]].map(\.id)]
        let plan = try #require(TidyLayout.plan(a + b, canvas: canvas, topInset: top, forcedGroups: groups))
        let boxes = groups.map { $0.map { rect($0, plan) }.reduce(CGRect.null) { $0.union($1) } }
        #expect(!boxes[0].intersects(boxes[1]))
        #expect(boxes.allSatisfy { $0.width < 480 && $0.height < 480 })
        // Порядок модели сохранён: первая карточка группы — в левом верхнем углу блока.
        #expect(rect(groups[0][0], plan).origin == boxes[0].origin)
    }

    @Test func cardsMissingFromForcedGroupsAreNotLost() throws {
        let items = (0..<5).map { item(CGFloat($0) * 200 + 30, 100) }
        let plan = try #require(TidyLayout.plan(items, canvas: canvas, topInset: top, forcedGroups: [[items[0].id, items[1].id], [items[2].id, UUID()]]))
        #expect(plan.count == 5)
    }

    @Test func denseBoardOf36CardsHasNoOverlaps() throws {
        // Как Space «Long»: 36 карточек, колонки по 6 + три тега, ~70% площади.
        let c = CGSize(width: 1000, height: 650)
        var items: [TidyLayout.Item] = []
        for i in 0..<36 {
            let tags: [String?] = [nil, nil, nil, "red", "orange", "blue"]
            items.append(item(CGFloat(i % 6) * 130 + 24, CGFloat(i / 6) * 100 + 50, tag: i % 7 == 0 ? tags[i % 6] ?? "red" : nil))
        }
        let plan = try #require(TidyLayout.plan(items, canvas: c, topInset: top))
        let rects = items.map { rect($0.id, plan) }
        for (i, r) in rects.enumerated() {
            for other in rects[(i + 1)...] { #expect(!r.intersects(other), "\(r) \(other)") }
        }
    }

    @Test func fewCardsFormOneEvenGrid() throws {
        // 7 разбросанных карточек: одна ровная сетка, без пустых мест и наложений.
        let items = (0..<7).map { item(CGFloat($0 * 170 % 900) + 40, CGFloat($0 * 130 % 500) + 60) }
        let plan = try #require(TidyLayout.plan(items, canvas: canvas, topInset: top))
        let rects = items.map { rect($0.id, plan) }
        #expect(Set(rects.map { $0.minX }).count <= 4)
        #expect(Set(rects.map { $0.minY }).count <= 3)
        for (i, r) in rects.enumerated() { for o in rects[(i + 1)...] { #expect(!r.intersects(o)) } }
    }

    @Test func nearSizesAreSnappedToOneSize() {
        let group = [item(0, 0, w: 158), item(0, 0, w: 164), item(0, 0, w: 166)]
        #expect(Set(TidyLayout.normalizedSizes(group).values.map(\.width)).count == 1)
    }

    @Test func midFillBoardUsesCorners() throws {
        // ~40% площади, две крупные группы: углы, а не одна сетка по центру.
        let c = CGSize(width: 1200, height: 800)
        func cluster(_ ox: CGFloat, _ oy: CGFloat, tag: String) -> [TidyLayout.Item] {
            (0..<8).map { item(ox + CGFloat($0 % 4) * 190, oy + CGFloat($0 / 4) * 190, w: 164, h: 164, tag: tag) }
        }
        let a = cluster(30, 60, tag: "red"), b = cluster(600, 400, tag: "blue")
        let plan = try #require(TidyLayout.plan(a + b, canvas: c, topInset: top))
        let ba = a.map { rect($0.id, plan) }.reduce(CGRect.null) { $0.union($1) }
        let bb = b.map { rect($0.id, plan) }.reduce(CGRect.null) { $0.union($1) }
        #expect(ba.minX < 40 && bb.maxX > c.width - 40)
    }

    @Test func crowdedBoardBecomesGridWithoutOverlaps() throws {
        // 23 крупных карточек (~55% площади): сетка, наложений нет.
        let c = CGSize(width: 1000, height: 650)
        let items = (0..<23).map { item(CGFloat($0 % 5) * 150 + 24, CGFloat($0 / 5) * 110 + 50, w: 164, h: 164) }
        let plan = try #require(TidyLayout.plan(items, canvas: c, topInset: top))
        let rects = items.map { rect($0.id, plan) }
        for (i, r) in rects.enumerated() { for o in rects[(i + 1)...] { #expect(!r.intersects(o)) } }
    }
}
