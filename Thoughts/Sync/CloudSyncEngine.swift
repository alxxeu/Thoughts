import AppKit
import CloudKit

/// Синк доски с приватной базой iCloud через CKSyncEngine (macOS 14+).
///
/// Локальный board.json остаётся источником правды и работает без сети;
/// движок лишь переносит изменения туда и обратно:
/// - локальные: BoardViewModel.persist → BoardChangeTracker → onLocalChanges
///   → pending changes движка → nextRecordZoneChangeBatch строит CKRecord
///   из текущего снимка доски (RecordMapping);
/// - удалённые: fetchedRecordZoneChanges → BoardViewModel.applyRemote,
///   который сливает их с локальными по группам полей (BoardMerger).
///
/// Правила конфликтов:
/// - одна карточка изменена на двух Mac → слияние по группам (content,
///   geometry, meta): побеждает более новая *ModifiedAt;
/// - удаление против правки → правка побеждает: карточка пересоздаётся,
///   данные не теряются.
///
/// Первое включение (или после смены аккаунта) — всегда с нуля: всё из
/// iCloud скачивается в буфер, и если данные есть и там, и здесь,
/// пользователь выбирает Merge / Use iCloud / Use This Mac. Перед этим
/// пишется локальный бэкап (AutomaticBackups).
/// Всё состояние — на главном акторе (как и сама доска); делегат CKSyncEngine
/// вызывается с его внутренней очереди и сразу переходит сюда.
@MainActor
final class CloudSyncEngine: CKSyncEngineDelegate {
    static let shared = CloudSyncEngine()

    private let settings = CloudSyncSettings.shared
    private let stateStore = SyncStateStore()
    private weak var viewModel: BoardViewModel?
    private var engine: CKSyncEngine?
    private var container: CKContainer?

    /// Первичная загрузка при включении: удалённые записи копятся здесь,
    /// а не применяются сразу, пока не станет ясно, что с ними делать.
    private var isInitialFetch = false
    private var initialCards: [UUID: CardRecord] = [:]
    private var initialWorkspaces: [Int: WorkspaceRecord] = [:]

    private var activationObserver: NSObjectProtocol?

    private init() {}

    // MARK: - Lifecycle

    /// Вызывается один раз при запуске (AppDelegate). Если синк был
    /// включён — поднимает движок с сохранённым состоянием.
    func start(viewModel: BoardViewModel) {
        self.viewModel = viewModel
        viewModel.onLocalChanges = { [weak self] changes in
            self?.enqueue(changes)
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.fetchChanges() }
        }

        guard settings.isEnabled else {
            settings.status = .off
            return
        }
        guard settings.isAvailableInBuild else {
            settings.status = .unavailable("iCloud isn\u{2019}t available in this build.")
            return
        }
        Task { await resume() }
    }

    /// Тумблер "Sync with iCloud" включили.
    func enable() async {
        guard settings.isAvailableInBuild, let viewModel else { return }
        let container = makeContainer()
        guard await checkAccount(container) else { return }

        AutomaticBackups.write(viewModel.makeSnapshot(), reason: "before-icloud-sync")
        stateStore.reset()
        settings.isEnabled = true
        KeychainSync.reconcile(showNotices: true)
        settings.status = .syncing

        let engine = makeEngine(container: container, state: nil)
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: RecordMapping.zoneID))])

        isInitialFetch = true
        initialCards = [:]
        initialWorkspaces = [:]
        do {
            try await engine.fetchChanges()
        } catch {
            // Без полной первичной сверки продолжать нельзя: локальные
            // данные так и не попали бы в очередь на отправку. Откатываемся
            // в "выключено" — повторное включение начнёт с нуля.
            isInitialFetch = false
            disable()
            fail(error)
            return
        }
        isInitialFetch = false
        await resolveInitialSync()
        await sendChanges()
    }

    /// Тумблер выключили: синк останавливается, локальные данные остаются,
    /// в iCloud ничего не удаляется. Состояние движка сбрасывается —
    /// следующее включение снова пройдёт через первичную сверку.
    func disable() {
        engine = nil
        stateStore.reset()
        settings.isEnabled = false
        settings.status = .off
    }

    /// "Delete iCloud Data…": удаляет зону целиком со всеми записями и
    /// выключает синк. Локальные данные не трогаются.
    func deleteCloudData() async -> Bool {
        guard settings.isAvailableInBuild else { return false }
        let container = container ?? makeContainer()
        do {
            _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [RecordMapping.zoneID])
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            // Нечего удалять — это тоже успех.
        } catch {
            fail(error)
            return false
        }
        disable()
        return true
    }

    /// "Sync Now" и активация приложения.
    func syncNow() async {
        await fetchChanges()
        await sendChanges()
    }

    // MARK: - Private: engine

    private func makeContainer() -> CKContainer {
        let container = self.container ?? CKContainer(identifier: RecordMapping.containerIdentifier)
        self.container = container
        return container
    }

    private func makeEngine(container: CKContainer, state: CKSyncEngine.State.Serialization?) -> CKSyncEngine {
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: state,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        NSApp.registerForRemoteNotifications()
        return engine
    }

    private func resume() async {
        let container = makeContainer()
        guard await checkAccount(container) else { return }
        guard let state = stateStore.loadEngineState() else {
            // Состояние потеряно (или его не было) — безопасно только
            // пройти первичную сверку заново.
            settings.isEnabled = false
            await enable()
            return
        }
        _ = makeEngine(container: container, state: state)
        KeychainSync.reconcile(showNotices: true)
        await syncNow()
    }

    private func checkAccount(_ container: CKContainer) async -> Bool {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                return true
            case .noAccount:
                settings.status = .unavailable("Sign in to iCloud in System Settings to sync.")
            case .restricted:
                settings.status = .unavailable("iCloud is restricted on this Mac.")
            case .temporarilyUnavailable:
                settings.status = .unavailable("iCloud is temporarily unavailable.")
            default:
                settings.status = .unavailable("iCloud account status is unknown.")
            }
        } catch {
            fail(error)
        }
        return false
    }

    private func fetchChanges() async {
        guard let engine else { return }
        do {
            try await engine.fetchChanges()
        } catch {
            fail(error)
        }
    }

    private func sendChanges() async {
        guard let engine else { return }
        do {
            try await engine.sendChanges()
        } catch {
            fail(error)
        }
    }

    // MARK: - Local changes → pending

    private func enqueue(_ changes: BoardChangeSet) {
        guard let engine, !isInitialFetch else { return }
        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        pending += changes.savedCards.map { .saveRecord(RecordMapping.recordID(forCard: $0)) }
        pending += changes.deletedCards.map { .deleteRecord(RecordMapping.recordID(forCard: $0)) }
        pending += changes.savedWorkspaces.map { .saveRecord(RecordMapping.recordID(forWorkspace: $0)) }
        engine.state.add(pendingRecordZoneChanges: pending)
    }

    private func enqueueEverythingLocal() {
        guard let engine, let viewModel else { return }
        let snapshot = viewModel.makeSnapshot()
        var pending: [CKSyncEngine.PendingRecordZoneChange] = snapshot.cards.map {
            .saveRecord(RecordMapping.recordID(forCard: $0.id))
        }
        pending += snapshot.workspaces.map { .saveRecord(RecordMapping.recordID(forWorkspace: $0.slot)) }
        engine.state.add(pendingRecordZoneChanges: pending)
    }

    // MARK: - First sync

    private func resolveInitialSync() async {
        guard let viewModel, let engine else { return }
        let remote = BoardSnapshot(
            workspaces: initialWorkspaces.values.sorted { $0.slot < $1.slot },
            cards: Array(initialCards.values)
        )
        initialCards = [:]
        initialWorkspaces = [:]

        let remoteIsEmpty = remote.cards.isEmpty
            && remote.workspaces.allSatisfy { $0.name == Workspace.defaultName(forSlot: $0.slot) && !$0.isProtected }

        if remoteIsEmpty {
            enqueueEverythingLocal()
            return
        }
        if viewModel.isBoardEmpty {
            viewModel.replaceWithRemote(remote)
            return
        }

        switch askInitialSyncChoice(remote: remote, local: viewModel.makeSnapshot()) {
        case .merge:
            viewModel.applyRemote(cards: remote.cards, deletedCardIDs: [], workspaces: remote.workspaces)
            // Объединение должно оказаться и в iCloud: карточки, которые
            // были только здесь, и те, где новее локальная версия.
            enqueueEverythingLocal()
        case .useCloud:
            viewModel.replaceWithRemote(remote)
        case .useThisMac:
            let localIDs = Set(viewModel.makeSnapshot().cards.map(\.id))
            let remoteOnly = remote.cards.map(\.id).filter { !localIDs.contains($0) }
            engine.state.add(pendingRecordZoneChanges: remoteOnly.map { .deleteRecord(RecordMapping.recordID(forCard: $0)) })
            enqueueEverythingLocal()
        }
    }

    private enum InitialChoice { case merge, useCloud, useThisMac }

    private func askInitialSyncChoice(remote: BoardSnapshot, local: BoardSnapshot) -> InitialChoice {
        let alert = NSAlert()
        alert.messageText = "Your Thoughts are already in iCloud"
        alert.informativeText = "iCloud has \(remote.cards.count) card\(remote.cards.count == 1 ? "" : "s") and this Mac has \(local.cards.count). "
            + "Merge keeps everything from both. A copy of this Mac\u{2019}s data has been saved as a backup."
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Use iCloud")
        alert.addButton(withTitle: "Use This Mac")
        switch alert.runModal() {
        case .alertSecondButtonReturn: return .useCloud
        case .alertThirdButtonReturn: return .useThisMac
        default: return .merge
        }
    }

    // MARK: - CKSyncEngineDelegate

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await handle(event, syncEngine: syncEngine)
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await makeBatch(context, syncEngine: syncEngine)
    }

    private func handle(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard syncEngine === engine else { return }

        switch event {
        case .stateUpdate(let update):
            stateStore.saveEngineState(update.stateSerialization)

        case .accountChange(let change):
            handleAccountChange(change)

        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == RecordMapping.zoneID }) {
                // Данные удалили с другого Mac ("Delete iCloud Data") —
                // локальные остаются, синк на этом Mac выключается.
                disable()
                settings.status = .unavailable("iCloud data was deleted from another Mac. Turn sync on again to upload this Mac\u{2019}s Thoughts.")
            }

        case .fetchedRecordZoneChanges(let changes):
            handleFetched(changes, syncEngine: syncEngine)

        case .sentRecordZoneChanges(let sent):
            handleSent(sent, syncEngine: syncEngine)

        case .willFetchChanges, .willSendChanges:
            if settings.isEnabled { settings.status = .syncing }

        case .didFetchChanges, .didSendChanges:
            if settings.isEnabled, case .syncing = settings.status {
                settings.status = .upToDate(Date())
            }

        default:
            break
        }
    }

    private func makeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard let viewModel, !isInitialFetch else { return nil }
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        let snapshot = viewModel.makeSnapshot()
        let cards = Dictionary(snapshot.cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let workspaces = Dictionary(snapshot.workspaces.map { ($0.slot, $0) }, uniquingKeysWith: { first, _ in first })

        // Сохранение карточки, которой локально уже нет (удалили после
        // постановки в очередь), — не отправляем: её удаление уже в очереди.
        var obsolete: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in pending {
            guard case .saveRecord(let recordID) = change,
                  case .card(let id) = RecordMapping.target(of: recordID),
                  cards[id] == nil else { continue }
            obsolete.append(change)
        }
        if !obsolete.isEmpty {
            syncEngine.state.remove(pendingRecordZoneChanges: obsolete)
        }
        let sendable = pending.filter { !obsolete.contains($0) }

        // CKRecord собираются здесь, на главном акторе (доска и кэш
        // системных полей живут на нём), а провайдер движка — который тот
        // вызывает со своей очереди — только отдаёт готовое.
        var records: [CKRecord.ID: CKRecord] = [:]
        for change in sendable {
            guard case .saveRecord(let recordID) = change else { continue }
            let base = stateStore.lastKnownRecord(for: recordID)
            switch RecordMapping.target(of: recordID) {
            case .card(let id):
                records[recordID] = cards[id].map { RecordMapping.record(for: $0, base: base) }
            case .workspace(let slot):
                records[recordID] = workspaces[slot].map { RecordMapping.record(for: $0, base: base) }
            case nil:
                break
            }
        }
        let prepared = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: sendable) { recordID in
            prepared[recordID]
        }
    }

    // MARK: - Private: events

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn:
            break
        case .signOut, .switchAccounts:
            // Локальные данные не трогаем — синк на паузу, состояние
            // сбрасываем. При следующем включении — первичная сверка с
            // выбором Merge / Use iCloud / Use This Mac.
            engine = nil
            stateStore.reset()
            settings.isEnabled = false
            settings.status = .unavailable("Your iCloud account changed. Turn sync on again to continue.")
        @unknown default:
            break
        }
    }

    private func handleFetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges, syncEngine: CKSyncEngine) {
        var cards: [CardRecord] = []
        var workspaces: [WorkspaceRecord] = []
        for modification in changes.modifications {
            let record = modification.record
            stateStore.remember(record)
            if let card = RecordMapping.cardRecord(from: record) {
                cards.append(card)
            } else if let workspace = RecordMapping.workspaceRecord(from: record) {
                workspaces.append(workspace)
            }
        }

        let pending = syncEngine.state.pendingRecordZoneChanges
        var deletedCards = Set<UUID>()
        for deletion in changes.deletions {
            stateStore.forget(deletion.recordID)
            guard case .card(let id) = RecordMapping.target(of: deletion.recordID) else { continue }
            // Удаление против локальной правки — правка побеждает: карточку
            // оставляем, её сохранение из очереди создаст запись заново.
            if pending.contains(.saveRecord(deletion.recordID)) { continue }
            deletedCards.insert(id)
        }

        // Правка с другого Mac против локального удаления — тоже побеждает
        // правка: убираем удаление из очереди, карточка вернётся.
        let resurrected = cards.map { CKSyncEngine.PendingRecordZoneChange.deleteRecord(RecordMapping.recordID(forCard: $0.id)) }
            .filter { pending.contains($0) }
        if !resurrected.isEmpty {
            syncEngine.state.remove(pendingRecordZoneChanges: resurrected)
        }

        if isInitialFetch {
            for card in cards { initialCards[card.id] = card }
            for id in deletedCards { initialCards[id] = nil }
            for workspace in workspaces { initialWorkspaces[workspace.slot] = workspace }
            return
        }
        viewModel?.applyRemote(cards: cards, deletedCardIDs: deletedCards, workspaces: workspaces)
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine) {
        for record in sent.savedRecords {
            stateStore.remember(record)
        }
        for recordID in sent.deletedRecordIDs {
            stateStore.forget(recordID)
        }

        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var needsZone = false
        for failure in sent.failedRecordSaves {
            let recordID = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                // Запись изменили на другом Mac после нашей последней
                // синхронизации — сливаем серверную версию с локальной и
                // отправляем результат поверх её change tag.
                guard let server = failure.error.serverRecord else { continue }
                stateStore.remember(server)
                if let card = RecordMapping.cardRecord(from: server) {
                    viewModel?.applyRemote(cards: [card], deletedCardIDs: [], workspaces: [])
                } else if let workspace = RecordMapping.workspaceRecord(from: server) {
                    viewModel?.applyRemote(cards: [], deletedCardIDs: [], workspaces: [workspace])
                }
                retry.append(.saveRecord(recordID))
            case .zoneNotFound, .userDeletedZone:
                needsZone = true
                stateStore.forget(recordID)
                retry.append(.saveRecord(recordID))
            case .unknownItem:
                // Запись удалили на сервере — правка побеждает, создаём заново.
                stateStore.forget(recordID)
                retry.append(.saveRecord(recordID))
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .requestRateLimited, .notAuthenticated, .operationCancelled:
                // Временное — движок повторит сам.
                break
            default:
                print("iCloud sync: failed to save \(recordID.recordName): \(failure.error)")
                settings.status = .failed(failure.error.localizedDescription)
            }
        }
        if needsZone {
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: RecordMapping.zoneID))])
        }
        if !retry.isEmpty {
            syncEngine.state.add(pendingRecordZoneChanges: retry)
        }
    }

    private func fail(_ error: Error) {
        print("iCloud sync error: \(error)")
        if let ckError = error as? CKError, [.networkFailure, .networkUnavailable].contains(ckError.code) {
            settings.status = .unavailable("Offline \u{2014} changes will sync when you\u{2019}re back online.")
        } else {
            settings.status = .failed(error.localizedDescription)
        }
    }
}
