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

    @Test func orderDefaultsSwapsAndPersists() {
        let defaults = makeDefaults()
        let settings = SpaceToolbarSettings(defaults: defaults)
        #expect(settings.order == ToolbarItem.allCases)
        settings.move(.clearSpace, to: 0, within: [.askAI, .tidyCards, .clearSpace])
        #expect(SpaceToolbarSettings(defaults: defaults).order == [.clearSpace, .askAI, .tidyCards, .lockSpace, .plugins])
        settings.move(.clearSpace, to: 2, within: [.clearSpace, .askAI, .tidyCards])
        #expect(settings.order == [.askAI, .tidyCards, .clearSpace, .lockSpace, .plugins])
        settings.reset()
        #expect(SpaceToolbarSettings(defaults: defaults).order == ToolbarItem.allCases)
    }

    @Test func storedOrderIgnoresUnknownAndAppendsNew() {
        let defaults = makeDefaults()
        defaults.set(["trashOld", "clearSpace", "askAI", "clearSpace"], forKey: "spaceToolbar.order")
        #expect(SpaceToolbarSettings(defaults: defaults).order == [.clearSpace, .askAI, .tidyCards, .lockSpace, .plugins])
    }
}
