import Foundation

/// Слияние двух версий доски или карточки — общие правила для импорта
/// бэкапа ("Add to My Thoughts") и для конфликтов синка с iCloud.
///
/// Карточка сливается по группам полей (см. Card): для content, geometry и
/// meta независимо побеждает версия с более поздней *ModifiedAt. Так правка
/// текста в одной версии и перемещение в другой не теряют друг друга. При
/// равенстве побеждает `base` (локальная версия).
enum BoardMerger {
    static func merge(_ base: CardRecord, _ other: CardRecord) -> CardRecord {
        var result = base

        if other.contentModifiedAt > base.contentModifiedAt {
            result.text = other.text
            result.formattingData = other.formattingData
            result.contentModifiedAt = other.contentModifiedAt
        }
        if other.geometryModifiedAt > base.geometryModifiedAt {
            result.x = other.x
            result.y = other.y
            result.width = other.width
            result.height = other.height
            result.raisedAt = other.raisedAt
            result.geometryModifiedAt = other.geometryModifiedAt
        }
        if other.metaModifiedAt > base.metaModifiedAt {
            result.workspaceSlot = other.workspaceSlot
            result.tagColor = other.tagColor
            result.privacyMode = other.privacyMode
            result.isAIGenerated = other.isAIGenerated
            result.metaModifiedAt = other.metaModifiedAt
        }
        return result
    }

    /// - Parameter keepProtection: true при импорте бэкапа — Space, защищённый
    ///   хоть в одной из версий, остаётся защищённым: импорт не должен
    ///   молча снимать Space Lock. При синке (false) побеждает более
    ///   новое решение пользователя, в том числе снятие защиты.
    static func merge(_ base: WorkspaceRecord, _ other: WorkspaceRecord, keepProtection: Bool) -> WorkspaceRecord {
        var result = other.modifiedAt > base.modifiedAt ? other : base

        // Своё имя всегда лучше дефолтного "Space N", даже если дефолтное новее.
        let baseIsDefault = base.name == Workspace.defaultName(forSlot: base.slot)
        let otherIsDefault = other.name == Workspace.defaultName(forSlot: other.slot)
        if baseIsDefault && !otherIsDefault {
            result.name = other.name
        } else if otherIsDefault && !baseIsDefault {
            result.name = base.name
        }

        if keepProtection {
            result.isProtected = base.isProtected || other.isProtected
        }
        return result
    }

    /// Объединение досок по ID карточек и слотам Spaces — "Add to My
    /// Thoughts" при импорте. Карточки есть только в одной версии —
    /// остаются; есть в обеих — сливаются по группам.
    static func merge(local: BoardSnapshot, incoming: BoardSnapshot) -> BoardSnapshot {
        var workspaces = Dictionary(local.workspaces.map { ($0.slot, $0) }, uniquingKeysWith: { first, _ in first })
        for workspace in incoming.workspaces {
            if let existing = workspaces[workspace.slot] {
                workspaces[workspace.slot] = merge(existing, workspace, keepProtection: true)
            } else {
                workspaces[workspace.slot] = workspace
            }
        }

        var cards = Dictionary(local.cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for card in incoming.cards {
            if let existing = cards[card.id] {
                cards[card.id] = merge(existing, card)
            } else {
                cards[card.id] = card
            }
        }

        return BoardSnapshot(
            workspaces: workspaces.values.sorted { $0.slot < $1.slot },
            cards: Array(cards.values)
        )
    }
}
