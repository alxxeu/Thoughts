import Foundation
import Observation

/// Доска как данные: Spaces и их карточки, сохранение на диск и всё, что
/// нужно синку с iCloud. Общая для Mac (её держит BoardViewModel, холст —
/// там) и iPhone.
@Observable
final class BoardModel: SyncableBoard {
    var workspaces: [Workspace] = []
    var cardsByWorkspace: [Int: [Card]] = [:]

    @ObservationIgnored private let store: BoardStore
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// См. BoardChangeTracker. Не наблюдается: это служебное состояние, не UI.
    @ObservationIgnored private var changeTracker: BoardChangeTracker!
    /// Изменения после каждого сохранения — сюда подписывается синк с iCloud.
    @ObservationIgnored var onLocalChanges: ((BoardChangeSet) -> Void)?
    /// После записи на диск; `true` — могло измениться то, что видно в
    /// Spotlight (на Mac — переиндексация).
    @ObservationIgnored var onSaved: ((_ contentChanged: Bool) -> Void)?
    /// Карточки, удалённые с другого устройства.
    @ObservationIgnored var onRemoteDeletion: ((Set<UUID>) -> Void)?
    /// После того как правки из iCloud применены и сохранены.
    @ObservationIgnored var onRemoteApplied: (() -> Void)?

    init(store: BoardStore = .shared) {
        self.store = store
        let loaded = store.load()
        workspaces = loaded.workspaces
        cardsByWorkspace = Self.normalizedZOrder(loaded.cardsByWorkspace)
        changeTracker = BoardChangeTracker(workspaces: workspaces, cardsByWorkspace: cardsByWorkspace)
    }

    /// Z-порядок держится на Card.raisedAt (см. комментарий там). У карточек,
    /// сохранённых до его появления, raisedAt неизвестен — выдаём им
    /// возрастающие "старые" значения по нынешнему порядку в массиве, чтобы
    /// ничего визуально не переставилось, и сортируем.
    static func normalizedZOrder(_ cardsByWorkspace: [Int: [Card]]) -> [Int: [Card]] {
        cardsByWorkspace.mapValues { cards in
            for (index, card) in cards.enumerated() where card.raisedAt == Card.unknownDate {
                card.raisedAt = Card.unknownDate.addingTimeInterval(Double(index + 1))
            }
            return sortedByZOrder(cards)
        }
    }

    static func sortedByZOrder(_ cards: [Card]) -> [Card] {
        // enumerated — стабильная сортировка при равных raisedAt.
        cards.enumerated()
            .sorted { ($0.element.raisedAt, $0.offset) < ($1.element.raisedAt, $1.offset) }
            .map(\.element)
    }

    // MARK: - Saving

    func saveImmediately() {
        persist(contentChanged: true)
    }

    /// Для чистого перемещения/ресайза карточки (drag-end/resize-end) —
    /// текст, приватность и имя Space не менялись, так что Spotlight-индекс
    /// не может стать неактуальным и полную переиндексацию всех Spaces
    /// запускать не нужно.
    func saveGeometry() {
        persist(contentChanged: false)
    }

    func scheduleDebouncedSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self else { return }
            self.persist(contentChanged: true)
        }
    }

    /// Досохраняет отложенное (debounced) сохранение прямо сейчас.
    func flushPendingSave() {
        guard saveTask != nil else { return }
        persist(contentChanged: true)
    }

    /// Единственная точка записи доски на диск. Перед записью трекер
    /// проставляет *ModifiedAt изменившимся карточкам/Spaces, после —
    /// изменения уходят подписчику (синку с iCloud).
    private func persist(contentChanged: Bool) {
        saveTask?.cancel()
        saveTask = nil

        var stampedWorkspaces = workspaces
        let changes = changeTracker.stamp(workspaces: &stampedWorkspaces, cardsByWorkspace: cardsByWorkspace)
        // Присваиваем, только если Space реально изменился: иначе каждое
        // сохранение дёргало бы всех наблюдателей workspaces (меню Spaces).
        if !changes.savedWorkspaces.isEmpty {
            workspaces = stampedWorkspaces
        }

        store.save(workspaces: workspaces, cardsByWorkspace: cardsByWorkspace)
        onSaved?(contentChanged)
        if !changes.isEmpty {
            onLocalChanges?(changes)
        }
    }

    // MARK: - Карточки (iPhone; на Mac — свои операции на холсте)

    /// Размер карточки с iPhone на холсте Mac — как у Quick Capture.
    static let phoneCardSize = CGSize(width: 224, height: 164)

    @discardableResult
    func addCard(text: String, slot: Int) -> Card {
        let card = Card(position: Card.unplacedPosition, size: Self.phoneCardSize, text: text)
        cardsByWorkspace[slot, default: []].append(card)
        saveImmediately()
        return card
    }

    /// Имя Space: обрезается до Workspace.maxNameLength, пустое — имя по умолчанию.
    func renameWorkspace(slot: Int, to name: String) {
        guard let index = workspaces.firstIndex(where: { $0.slot == slot }) else { return }
        let limited = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Workspace.maxNameLength))
        workspaces[index].name = limited.isEmpty ? Workspace.defaultName(forSlot: slot) : limited
        saveImmediately()
    }

    func deleteCard(id: UUID) {
        for slot in cardsByWorkspace.keys {
            cardsByWorkspace[slot]?.removeAll { $0.id == id }
        }
        saveImmediately()
    }

    // MARK: - Snapshot (бэкап, импорт, синк)

    func makeSnapshot() -> BoardSnapshot {
        BoardSnapshot(
            workspaces: workspaces.map { WorkspaceRecord($0) },
            cards: cardsByWorkspace.flatMap { slot, cards in cards.map { CardRecord($0, slot: slot) } }
        )
    }

    /// Импорт бэкапа: `replacing` — доска становится ровно такой, как в
    /// бэкапе; иначе бэкап сливается с текущими данными (BoardMerger).
    /// Перед вызовом нужна страховочная копия (AutomaticBackups) — это
    /// делает BackupCoordinator.
    func applyImported(_ snapshot: BoardSnapshot, replacing: Bool) {
        let result = replacing ? snapshot : BoardMerger.merge(local: makeSnapshot(), incoming: snapshot)
        replaceBoard(with: result)
        saveImmediately()
    }

    /// Пересобирает доску из снимка. Карточки с уже существующими ID
    /// обновляются на месте — их CardView не пересоздаются, открытый
    /// редактор не теряет состояние.
    private func replaceBoard(with snapshot: BoardSnapshot) {
        let existingCards = Dictionary(
            cardsByWorkspace.values.flatMap { $0 }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var newCards: [Int: [Card]] = [:]
        for record in snapshot.cards {
            let card: Card
            if let existing = existingCards[record.id] {
                record.apply(to: existing)
                card = existing
            } else {
                card = record.makeCard()
            }
            newCards[record.workspaceSlot, default: []].append(card)
        }

        let recordsBySlot = Dictionary(snapshot.workspaces.map { ($0.slot, $0) }, uniquingKeysWith: { first, _ in first })
        workspaces = workspaces.map { workspace in
            guard let record = recordsBySlot[workspace.slot] else { return workspace }
            var updated = workspace
            updated.name = record.name
            updated.isProtected = record.isProtected
            updated.modifiedAt = record.modifiedAt
            return updated
        }
        cardsByWorkspace = newCards.mapValues { Self.sortedByZOrder($0) }
    }

    // MARK: - Remote changes (iCloud)

    /// Карточка, в которой сейчас текстовый курсор (выставляет UI).
    /// Удалённая правка её текста откладывается до ухода фокуса — иначе
    /// текст менялся бы прямо под курсором.
    var editingCardID: UUID? {
        didSet {
            guard let previous = oldValue, previous != editingCardID,
                  let deferred = deferredRemoteContent.removeValue(forKey: previous) else { return }
            applyRemote(cards: [deferred], deletedCardIDs: [], workspaces: [])
        }
    }
    @ObservationIgnored private var deferredRemoteContent: [UUID: CardRecord] = [:]

    /// Пусто ли на этом устройстве — для первого включения синка: пустую
    /// доску можно просто заполнить из iCloud, ничего не спрашивая.
    var isBoardEmpty: Bool {
        cardsByWorkspace.values.allSatisfy(\.isEmpty)
            && workspaces.allSatisfy { $0.name == Workspace.defaultName(forSlot: $0.slot) && !$0.isProtected }
    }

    /// Правки, пришедшие из iCloud. Каждая карточка сливается с локальной
    /// по группам полей (BoardMerger) — локальные несинхронизированные
    /// правки не теряются. Результат сохраняется на диск, но не считается
    /// локальным изменением (трекер принимает его как уже синхронизированный),
    /// иначе он тут же ушёл бы обратно в iCloud.
    func applyRemote(cards incoming: [CardRecord], deletedCardIDs: Set<UUID>, workspaces incomingWorkspaces: [WorkspaceRecord]) {
        guard !incoming.isEmpty || !deletedCardIDs.isEmpty || !incomingWorkspaces.isEmpty else { return }
        // Сначала — несохранённые локальные правки (отложенное сохранение
        // текста): они должны получить свои *ModifiedAt и уйти в очередь
        // до слияния, а не потеряться под удалённой версией.
        flushPendingSave()

        var located: [UUID: (card: Card, slot: Int)] = [:]
        for (slot, cards) in cardsByWorkspace {
            for card in cards { located[card.id] = (card, slot) }
        }

        var accepted: [(card: Card, slot: Int)] = []
        var touchedSlots = Set<Int>()

        for remote in incoming {
            guard let (card, slot) = located[remote.id] else {
                let card = remote.makeCard()
                cardsByWorkspace[remote.workspaceSlot, default: []].append(card)
                touchedSlots.insert(remote.workspaceSlot)
                accepted.append((card, remote.workspaceSlot))
                continue
            }

            let local = CardRecord(card, slot: slot)
            var merged = BoardMerger.merge(local, remote)
            if card.id == editingCardID,
               merged.text != local.text {
                deferredRemoteContent[card.id] = remote
                merged.text = local.text
                merged.contentModifiedAt = local.contentModifiedAt
            }

            if merged != local {
                merged.apply(to: card)
                if merged.workspaceSlot != slot {
                    cardsByWorkspace[slot]?.removeAll { $0.id == card.id }
                    cardsByWorkspace[merged.workspaceSlot, default: []].append(card)
                    touchedSlots.insert(slot)
                }
                touchedSlots.insert(merged.workspaceSlot)
            }
            accepted.append((card, merged.workspaceSlot))
        }

        for id in deletedCardIDs {
            guard let (_, slot) = located[id] else { continue }
            cardsByWorkspace[slot]?.removeAll { $0.id == id }
            deferredRemoteContent[id] = nil
        }
        if !deletedCardIDs.isEmpty {
            onRemoteDeletion?(deletedCardIDs)
        }

        var acceptedWorkspaces: [Workspace] = []
        if !incomingWorkspaces.isEmpty {
            var updated = workspaces
            for remote in incomingWorkspaces {
                guard let index = updated.firstIndex(where: { $0.slot == remote.slot }) else { continue }
                let merged = BoardMerger.merge(WorkspaceRecord(updated[index]), remote, keepProtection: false)
                updated[index].name = merged.name
                updated[index].isProtected = merged.isProtected
                updated[index].modifiedAt = merged.modifiedAt
                acceptedWorkspaces.append(updated[index])
            }
            if updated != workspaces {
                workspaces = updated
            }
        }

        for slot in touchedSlots {
            cardsByWorkspace[slot] = Self.sortedByZOrder(cardsByWorkspace[slot] ?? [])
        }

        store.save(workspaces: workspaces, cardsByWorkspace: cardsByWorkspace)
        onSaved?(true)
        changeTracker.accept(cards: accepted, deletedCards: deletedCardIDs, workspaces: acceptedWorkspaces)
        onRemoteApplied?()
    }

    /// "Use iCloud" при первом включении синка: доска становится ровно
    /// такой, как в iCloud, и считается уже синхронизированной.
    func replaceWithRemote(_ snapshot: BoardSnapshot) {
        saveTask?.cancel()
        saveTask = nil
        deferredRemoteContent = [:]
        replaceBoard(with: snapshot)
        store.save(workspaces: workspaces, cardsByWorkspace: cardsByWorkspace)
        onSaved?(true)
        changeTracker.rebaseline(workspaces: workspaces, cardsByWorkspace: cardsByWorkspace)
    }
}
