import Foundation
import Testing
@testable import Thoughts

struct FailedTapCounterTests {
    @Test func thirdQuickFailureTriggersAndRestarts() {
        var counter = FailedTapCounter()
        let t = Date()
        let results = [0.0, 0.5, 1, 1.5].map { counter.fail(at: t.addingTimeInterval($0)) }
        #expect(results == [false, false, true, false])
    }

    @Test func pauseOrSuccessStartsOver() {
        var counter = FailedTapCounter()
        let t = Date()
        let afterPause = [0.0, 1, 10].map { counter.fail(at: t.addingTimeInterval($0)) }
        #expect(afterPause == [false, false, false])
        counter.reset()
        let afterReset = [11.0, 12].map { counter.fail(at: t.addingTimeInterval($0)) }
        #expect(afterReset == [false, false])
    }
}
