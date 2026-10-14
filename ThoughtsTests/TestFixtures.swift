import Foundation
@testable import Thoughts

func makeCardRecord(
    id: UUID = UUID(),
    slot: Int = 1,
    text: String = "Hello",
    x: Double = 40,
    width: Double = 104,
    contentAt: TimeInterval = 100,
    geometryAt: TimeInterval = 100,
    metaAt: TimeInterval = 100
) -> CardRecord {
    CardRecord(
        id: id,
        workspaceSlot: slot,
        text: text,
        x: x,
        y: 60,
        width: width,
        height: 104,
        raisedAt: Date(timeIntervalSince1970: 1),
        tagColor: CardTagColor.blue.rawValue,
        privacyMode: CardPrivacyMode.none.rawValue,
        isAIGenerated: false,
        contentModifiedAt: Date(timeIntervalSince1970: contentAt),
        geometryModifiedAt: Date(timeIntervalSince1970: geometryAt),
        metaModifiedAt: Date(timeIntervalSince1970: metaAt)
    )
}
