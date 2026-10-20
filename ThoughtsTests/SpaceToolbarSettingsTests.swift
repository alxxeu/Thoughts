import Foundation
import Testing
@testable import Thoughts

@MainActor
struct SpaceToolbarSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "toolbar-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func hidingPersistsAndResets() {
        let defaults = makeDefaults()
        let settings = SpaceToolbarSettings(defaults: defaults)
        #expect(settings.hidden.isEmpty)
        settings.setHidden(.askAI, true)
        settings.setHidden(.plugins, true)
        #expect(SpaceToolbarSettings(defaults: defaults).hidden == [.askAI, .plugins])
        settings.setHidden(.askAI, false)
        #expect(SpaceToolbarSettings(defaults: defaults).hidden == [.plugins])
        settings.reset()
        #expect(SpaceToolbarSettings(defaults: defaults).hidden.isEmpty)
    }

    @Test func everythingCanBeHidden() {
        let settings = SpaceToolbarSettings(defaults: makeDefaults())
        ToolbarItem.allCases.forEach { settings.setHidden($0, true) }
        #expect(settings.hidden.count == ToolbarItem.allCases.count)
    }

    @Test func unknownStoredItemsAreIgnored() {
        let defaults = makeDefaults()
        defaults.set(["askAI", "somethingNew"], forKey: "spaceToolbar.hiddenItems")
        #expect(SpaceToolbarSettings(defaults: defaults).hidden == [.askAI])
    }
}
