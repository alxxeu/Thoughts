import Foundation

/// Что изменилось с последнего сохранения — ровно то, что нужно отправить
/// в iCloud (см. CloudSyncEngine).
struct BoardChangeSet: Equatable {
    var savedCards: Set<UUID> = []
    var deletedCards: Set<UUID> = []
    var savedWorkspaces: Set<Int> = []

    var isEmpty: Bool {
        savedCards.isEmpty && deletedCards.isEmpty && savedWorkspaces.isEmpty
    }
}

/// Находит изменения доски сравнением с последним сохранённым снимком, а не
/// через отметки в каждой точке мутации: все пути сохранения и так сходятся
/// в BoardViewModel.persist, а мест, где меняются карточки (текст, драг,
/// ресайз, теги, Tidy, AI, Quick Capture, Clear Space…), слишком много,
/// чтобы надёжно не забыть ни одно.
///
/// Изменившейся группе полей карточки (content / geometry / meta, см. Card)
/// ставится свежая *ModifiedAt — по ним потом сливаются правки с разных Mac
/// и из бэкапа (BoardMerger).
final class BoardChangeTracker {
    private struct CardFingerprint: Equatable {
        var content: Int
        var geometry: Int
        var meta: Int
    }

    private var cardFingerprints: [UUID: CardFingerprint] = [:]
    private var workspaceFingerprints: [Int: Int] = [:]

    init(workspaces: [Workspace], cardsByWorkspace: [Int: [Card]]) {
        rebaseline(workspaces: workspaces, cardsByWorkspace: cardsByWorkspace)
    }

    /// Сравнивает текущее состояние со снимком, проставляет *ModifiedAt
    /// изменившимся группам и запоминает новое состояние как снимок.
    func stamp(workspaces: inout [Workspace], cardsByWorkspace: [Int: [Card]], now: Date = Date()) -> BoardChangeSet {
        var changes = BoardChangeSet()
        var seen = Set<UUID>()

        for (slot, slotCards) in cardsByWorkspace {
            for card in slotCards {
                seen.insert(card.id)
                let current = Self.fingerprint(card, slot: slot)
                let previous = cardFingerprints[card.id]
                guard current != previous else { continue }

                if previous == nil || previous?.content != current.content {
                    card.contentModifiedAt = now
                }
                if previous == nil || previous?.geometry != current.geometry {
                    card.geometryModifiedAt = now
                }
                if previous == nil || previous?.meta != current.meta {
                    card.metaModifiedAt = now
                }
                cardFingerprints[card.id] = current
                changes.savedCards.insert(card.id)
            }
        }

        for id in cardFingerprints.keys where !seen.contains(id) {
            changes.deletedCards.insert(id)
        }
        for id in changes.deletedCards {
            cardFingerprints[id] = nil
        }

        for index in workspaces.indices {
            let workspace = workspaces[index]
            let current = Self.fingerprint(workspace)
            guard workspaceFingerprints[workspace.slot] != current else { continue }
            workspaces[index].modifiedAt = now
            workspaceFingerprints[workspace.slot] = current
            changes.savedWorkspaces.insert(workspace.slot)
        }

        return changes
    }

    /// Принять состояние как уже синхронизированное, ничего не помечая
    /// изменённым: после загрузки с диска и после применения правок,
    /// пришедших из iCloud (иначе они тут же ушли бы обратно эхом).
    func rebaseline(workspaces: [Workspace], cardsByWorkspace: [Int: [Card]]) {
        cardFingerprints = [:]
        for (slot, slotCards) in cardsByWorkspace {
            for card in slotCards {
                cardFingerprints[card.id] = Self.fingerprint(card, slot: slot)
            }
        }
        workspaceFingerprints = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.slot, Self.fingerprint($0)) })
    }

    /// Точечный вариант rebaseline — только для перечисленных карточек и
    /// Spaces. Остальные локальные изменения, ещё не прошедшие через stamp,
    /// при этом не теряются.
    func accept(cards: [(card: Card, slot: Int)], deletedCards: Set<UUID>, workspaces: [Workspace]) {
        for (card, slot) in cards {
            cardFingerprints[card.id] = Self.fingerprint(card, slot: slot)
        }
        for id in deletedCards {
            cardFingerprints[id] = nil
        }
        for workspace in workspaces {
            workspaceFingerprints[workspace.slot] = Self.fingerprint(workspace)
        }
    }

    // MARK: - Fingerprints

    private static func fingerprint(_ card: Card, slot: Int) -> CardFingerprint {
        var content = Hasher()
        content.combine(card.text)
        content.combine(card.formattingData)

        var geometry = Hasher()
        geometry.combine(card.position.x)
        geometry.combine(card.position.y)
        geometry.combine(card.size.width)
        geometry.combine(card.size.height)
        geometry.combine(card.raisedAt)

        var meta = Hasher()
        meta.combine(slot)
        meta.combine(card.tagColor)
        meta.combine(card.privacyMode)
        meta.combine(card.isAIGenerated)

        return CardFingerprint(content: content.finalize(), geometry: geometry.finalize(), meta: meta.finalize())
    }

    private static func fingerprint(_ workspace: Workspace) -> Int {
        var hasher = Hasher()
        hasher.combine(workspace.name)
        hasher.combine(workspace.isProtected)
        return hasher.finalize()
    }
}
