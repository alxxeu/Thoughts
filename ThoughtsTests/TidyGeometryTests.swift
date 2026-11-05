import CoreGraphics
import Foundation
import Testing
@testable import Thoughts

struct TidyGeometryTests {
    private let small = BoardViewModel.minCardSize // 104

    private func item(w: CGFloat, h: CGFloat? = nil) -> TidyGeometry.Item {
        TidyGeometry.Item(id: UUID(), size: CGSize(width: w, height: h ?? small))
    }

    @Test func nearSizesAreSnappedToOne() {
        let group = [item(w: 158), item(w: 164), item(w: 166)]
        #expect(Set(TidyGeometry.normalizedSizes(group).values.map(\.width)).count == 1)
    }

    @Test func majoritySizeIsAdoptedByEveryone() {
        let group = [item(w: small), item(w: small), item(w: small), item(w: small), item(w: 224, h: 164)]
        #expect(TidyGeometry.normalizedSizes(group).values.allSatisfy { $0 == CGSize(width: small, height: small) })
    }

    @Test func nearOutlierOnlyGrows() {
        let wide = BoardViewModel.snap(164)
        let group = [item(w: wide), item(w: wide), item(w: small), item(w: small + 60)]
        #expect(TidyGeometry.normalizedSizes(group)[group[2].id]?.width == wide)
    }

    @Test func intentionalMixIsLeftAlone() {
        let big = item(w: 344, h: 344)
        let group = [item(w: small), item(w: small), big, item(w: 344, h: 344)]
        #expect(TidyGeometry.normalizedSizes(group)[big.id] == big.size)
    }
}
