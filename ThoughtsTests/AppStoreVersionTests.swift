import Testing
@testable import Thoughts

struct AppStoreVersionTests {
    @Test func comparesVersionsNumerically() {
        #expect(AppStoreVersion.isNewer("1.4", than: "1.3"))
        #expect(AppStoreVersion.isNewer("1.10", than: "1.9"))
        #expect(AppStoreVersion.isNewer("1.4.1", than: "1.4"))
        #expect(!AppStoreVersion.isNewer("1.4", than: "1.4"))
        #expect(!AppStoreVersion.isNewer("1.3", than: "1.4"))
    }
}
