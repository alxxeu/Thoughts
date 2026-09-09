import AppKit
import LocalAuthentication
import SwiftUI

enum EdgeHint: Equatable {
    enum Edge { case top, left, right, bottom }
    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    case edge(Edge, CGRect)
    case corner(Corner, CGRect)
}

@Observable
final class BoardViewModel {
    var workspaces: [Workspace] = []
    var activeSlot: Int = 1
    private var cardsByWorkspace: [Int: [Card]] = [:]

    let securitySettings = SecuritySettings.shared
    let appearanceSettings = AppearanceSettings.shared

    /// Слоты защищённых (Workspace.isProtected == true) Space, прошедшие
    /// аутентификацию в ЭТОЙ сессии. Runtime-only, никогда не персистится:
    /// при старте приложения всегда пусто, поэтому любой защищённый Space
    /// стартует заблокированным. Отдельно от Workspace.isProtected —
    /// именно поэтому после успешной разблокировки Space "числится как
    /// имеющий блокировку", но при этом сейчас открыт.
    private var unlockedProtectedSlots: Set<Int> = []
    private var idleLockTasks: [Int: Task<Void, Never>] = [:]

    var isActiveSpaceLocked: Bool {
        securitySettings.isPasscodeEnabled
            && (activeWorkspace?.isProtected ?? false)
            && !unlockedProtectedSlots.contains(activeSlot)
    }

    var cards: [Card] {
        get { cardsByWorkspace[activeSlot] ?? [] }
        set { cardsByWorkspace[activeSlot] = newValue }
    }

    var activeWorkspace: Workspace? {
        workspaces.first { $0.slot == activeSlot }
    }

    private let store = BoardStore.shared
    private var saveTask: Task<Void, Never>?

    static let cardSizeStep: CGFloat = 60
    /// Зазор между стыкующимися карточками — тот же, что использует
    /// placementPreview при стековке. Обе величины обязаны идти из одной
    /// константы: card-size формула size(k) = k*cardSizeStep - cardGap
    /// устроена так, что любые две стыкующиеся карточки (k1 и k2 тайлов)
    /// с этим зазором между ними в сумме дают ровно size(k1+k2) — то есть
    /// колонка из нескольких карточек всегда идеально совпадает по краю
    /// с одной карточкой такой же суммарной "тайловости", как у нативных
    /// виджетов macOS (medium = 2 tile + 1 gap, а не просто 2 tile).
    static let cardGap: CGFloat = 16
    static let minCardSize: CGFloat = 2 * cardSizeStep - cardGap
    static let canvasSidePadding: CGFloat = 24
    static let topCreationLimit: CGFloat = 40
    static let maxWorkspaceNameLength = 30

    init() {
        let loaded = store.load()
        workspaces = loaded.workspaces
        cardsByWorkspace = loaded.cardsByWorkspace
        reindexSpotlight()
    }

    static func snap(_ value: CGFloat) -> CGFloat {
        let tiles = max(2, ((value + cardGap) / cardSizeStep).rounded())
        return tiles * cardSizeStep - cardGap
    }

    func switchWorkspace(to slot: Int) {
        // Переключение между Spaces больше не трогает лок-состояние —
        // каждый Space независим: незащищённые остаются как есть,
        // защищённые сохраняют своё locked/unlocked ровно таким, каким его
        // оставили в прошлый раз (или каким его успел сделать idle-таймер
        // в фоне, пока Space не был активен).
        activeSlot = min(9, max(1, slot))
    }

    // MARK: - Space Lock

    /// Разблокировывает текущий активный Space и запускает его idle-таймер
    /// (если Auto-Lock не выключен). Вызывается из SpaceLockOverlayView
    /// после успешного прохождения выбранного способа разблокировки.
    /// Workspace.isProtected при этом НЕ меняется — Space по-прежнему
    /// "числится" защищённым, просто сейчас открыт.
    func unlockActiveSpace() {
        unlockedProtectedSlots.insert(activeSlot)
        scheduleIdleLock(for: activeSlot)
    }

    /// Cmd+L — включает защиту для текущего Space (если ещё не включена) и
    /// сразу блокирует его. No-op, если мастер-переключатель Space Lock
    /// выключен в Security-настройках, или Space уже и так заблокирован
    /// (повторное нажатие на lock screen не должно ничего запускать заново).
    func lockActiveSpaceManually() {
        guard securitySettings.isPasscodeEnabled, !isActiveSpaceLocked else { return }
        setSpaceProtected(true, slot: activeSlot)
    }

    /// Включает/выключает защиту для произвольного (не обязательно
    /// активного) Space — используется списком переключателей в Security
    /// Settings (замена прежнему Cmd+Shift+L). Включение сразу блокирует
    /// Space; выключение сразу открывает его без аутентификации, так как
    /// сам доступ к этому списку в Settings уже требует, чтобы активный
    /// Space не был заблокирован (см. SettingsView).
    func setSpaceProtected(_ isProtected: Bool, slot: Int) {
        guard let index = workspaces.firstIndex(where: { $0.slot == slot }) else { return }
        workspaces[index].isProtected = isProtected
        relock(slot: slot)
        saveImmediately()
    }

    /// Единая точка входа для сброса idle-таймера — вызывается из
    /// централизованного NSEvent-монитора в AppDelegate на любое
    /// взаимодействие пользователя (клик, драг, ввод текста, скролл,
    /// движение мыши и т.д.), а не из отдельных компонентов. Сбрасывает
    /// таймер только активного Space — с другими Space пользователь
    /// физически не может взаимодействовать, пока они не выбраны.
    func recordInteraction() {
        guard unlockedProtectedSlots.contains(activeSlot) else { return }
        scheduleIdleLock(for: activeSlot)
    }

    /// Не создаёт нового таймера на каждое взаимодействие — переиспользует
    /// тот же паттерн, что и scheduleDebouncedSave: отменить предыдущий
    /// Task и поставить новый. У каждого разблокированного защищённого
    /// Space — свой собственный такой Task, поэтому auto-lock срабатывает
    /// независимо для каждого, даже пока пользователь работает в другом.
    private func scheduleIdleLock(for slot: Int) {
        idleLockTasks[slot]?.cancel()
        idleLockTasks[slot] = nil

        guard securitySettings.autoLockInterval != .never else { return }

        let interval = securitySettings.autoLockInterval.rawValue
        idleLockTasks[slot] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.relock(slot: slot)
        }
    }

    private func relock(slot: Int) {
        idleLockTasks[slot]?.cancel()
        idleLockTasks[slot] = nil
        unlockedProtectedSlots.remove(slot)
        if slot == activeSlot {
            // Нельзя оставлять активный NSTextView под lock overlay —
            // снимаем фокус тем же способом, что уже используется при
            // клике по пустому холсту в ContentView.
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }


    func renameActiveWorkspace(to name: String) {
        guard let index = workspaces.firstIndex(where: { $0.slot == activeSlot }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(Self.maxWorkspaceNameLength))
        workspaces[index].name = limited.isEmpty ? Workspace.defaultName(forSlot: activeSlot) : limited
        saveImmediately()
    }

    @discardableResult
    func addCard(at origin: CGPoint, size: CGSize) -> Card {
        let snapped = CGSize(width: Self.snap(size.width), height: Self.snap(size.height))
        let card = Card(position: origin, size: snapped)
        cards.append(card)
        saveImmediately()
        return card
    }

    func deleteCard(_ card: Card) {
        cards.removeAll { $0.id == card.id }
        saveImmediately()
    }

    /// File → Clear Space, после подтверждения в алерте (см. ContentView).
    /// Необратимо — сама эта функция ничего не спрашивает, вызывающая
    /// сторона обязана получить согласие пользователя заранее.
    func clearActiveSpace() {
        cards = []
        saveImmediately()
    }

    func bringToFront(_ card: Card) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        var current = cards
        current.append(current.remove(at: index))
        cards = current
    }

    func saveImmediately() {
        saveTask?.cancel()
        saveTask = nil
        store.save(workspaces: workspaces, cardsByWorkspace: cardsByWorkspace)
        reindexSpotlight()
    }

    func scheduleDebouncedSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self else { return }
            self.store.save(workspaces: self.workspaces, cardsByWorkspace: self.cardsByWorkspace)
            self.reindexSpotlight()
        }
    }

    private func reindexSpotlight() {
        // Space Lock — как и per-card Spoiler/Lock — не должен утекать через
        // системный поиск: карточки любого Space с isProtected == true
        // целиком исключаются из индекса, независимо от того, разблокирован
        // ли этот Space прямо сейчас в текущей сессии (unlockedProtectedSlots
        // — это только runtime-состояние UI, не сигнал "больше не приватно").
        let snapshots = workspaces.filter { !$0.isProtected }.flatMap { workspace in
            (cardsByWorkspace[workspace.slot] ?? []).map {
                SpotlightCardSnapshot(
                    id: $0.id,
                    text: $0.text,
                    privacyMode: $0.privacyMode,
                    workspaceName: workspace.name
                )
            }
        }
        SpotlightIndexer.reindexAll(snapshots)
    }

    /// Находит карточку и её спэйс по идентификатору, полученному из
    /// Spotlight-активности.
    func locateCard(id: UUID) -> (workspace: Workspace, card: Card)? {
        for workspace in workspaces {
            if let card = (cardsByWorkspace[workspace.slot] ?? []).first(where: { $0.id == id }) {
                return (workspace, card)
            }
        }
        return nil
    }

    /// Переключает на спэйс с искомой карточкой и просит её подсветиться.
    /// Небольшая задержка — чтобы CardView для нужного спэйса успел
    /// подписаться на уведомление после переключения (по аналогии с
    /// задержкой перед FocusNewCard для только что созданных карточек).
    func focusOnCard(id: UUID) {
        guard let located = locateCard(id: id) else { return }
        switchWorkspace(to: located.workspace.slot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .highlightCard, object: id)
        }
    }

    func authenticateWithTouchID(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) ||
           context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = "Разблокировать карточку"
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        } else {
            // Touch ID/device-password недоступны — НЕ считаем это успехом.
            // Passcode остаётся основным и всегда рабочим путём разблокировки;
            // здесь fail-closed, а не fail-open.
            DispatchQueue.main.async {
                completion(false)
            }
        }
    }
}

extension BoardViewModel {
    static func placementPreview(
        movingId: UUID,
        movingPosition: CGPoint,
        movingSize: CGSize,
        others: [Card],
        canvasSize: CGSize
    ) -> CGPoint? {
        let gap = cardGap
        let activationDistance: CGFloat = 45
        let pad = canvasSidePadding
        let top = topCreationLimit
        let cardW = movingSize.width
        let cardH = movingSize.height

        var best: (distance: CGFloat, point: CGPoint)?

        func consider(_ x: CGFloat, _ y: CGFloat) {
            let distance = hypot(movingPosition.x - x, movingPosition.y - y)
            guard distance <= activationDistance else { return }
            if best == nil || distance < best!.distance {
                best = (distance, CGPoint(x: x, y: y))
            }
        }

        for other in others where other.id != movingId {
            let oPos = other.position
            let oSize = other.size

            let rightX = oPos.x + oSize.width + gap
            for y in [oPos.y, oPos.y + oSize.height - cardH] {
                if rightX + cardW <= canvasSize.width - pad,
                   y >= top,
                   y + cardH <= canvasSize.height - pad {
                    consider(rightX, y)
                }
            }

            let leftX = oPos.x - cardW - gap
            for y in [oPos.y, oPos.y + oSize.height - cardH] {
                if leftX >= pad,
                   y >= top,
                   y + cardH <= canvasSize.height - pad {
                    consider(leftX, y)
                }
            }

            let bottomY = oPos.y + oSize.height + gap
            for x in [oPos.x, oPos.x + oSize.width - cardW] {
                if x >= pad,
                   x + cardW <= canvasSize.width - pad,
                   bottomY + cardH <= canvasSize.height - pad {
                    consider(x, bottomY)
                }
            }

            let topY = oPos.y - cardH - gap
            for x in [oPos.x, oPos.x + oSize.width - cardW] {
                if x >= pad,
                   x + cardW <= canvasSize.width - pad,
                   topY >= top {
                    consider(x, topY)
                }
            }
        }

        return best?.point
    }

    static func edgeHints(
        movingPosition: CGPoint,
        movingSize: CGSize,
        canvasSize: CGSize
    ) -> [EdgeHint] {
        let pad = canvasSidePadding
        let top = topCreationLimit
        let lineThreshold: CGFloat = 35
        let cornerZone: CGFloat = 120
        let armLength: CGFloat = 60

        let distTop = movingPosition.y - top
        let distLeft = movingPosition.x - pad
        let distRight = canvasSize.width - pad - movingPosition.x - movingSize.width
        let distBottom = canvasSize.height - pad - movingPosition.y - movingSize.height

        struct CornerCandidate {
            let corner: EdgeHint.Corner
            let score: CGFloat
        }

        var candidates: [CornerCandidate] = []
        if distTop <= cornerZone && distLeft <= cornerZone {
            candidates.append(.init(corner: .topLeft, score: distTop + distLeft))
        }
        if distTop <= cornerZone && distRight <= cornerZone {
            candidates.append(.init(corner: .topRight, score: distTop + distRight))
        }
        if distBottom <= cornerZone && distLeft <= cornerZone {
            candidates.append(.init(corner: .bottomLeft, score: distBottom + distLeft))
        }
        if distBottom <= cornerZone && distRight <= cornerZone {
            candidates.append(.init(corner: .bottomRight, score: distBottom + distRight))
        }

        if let best = candidates.min(by: { $0.score < $1.score }) {
            let frame: CGRect
            switch best.corner {
            case .topLeft:
                frame = CGRect(x: pad, y: top, width: armLength, height: armLength)
            case .topRight:
                frame = CGRect(x: canvasSize.width - pad - armLength, y: top, width: armLength, height: armLength)
            case .bottomLeft:
                frame = CGRect(x: pad, y: canvasSize.height - pad - armLength, width: armLength, height: armLength)
            case .bottomRight:
                frame = CGRect(x: canvasSize.width - pad - armLength, y: canvasSize.height - pad - armLength, width: armLength, height: armLength)
            }
            return [.corner(best.corner, frame)]
        }

        var hints: [EdgeHint] = []
        if distTop <= lineThreshold {
            hints.append(.edge(.top, CGRect(x: movingPosition.x, y: top, width: movingSize.width, height: 3)))
        }
        if distBottom <= lineThreshold {
            hints.append(.edge(.bottom, CGRect(x: movingPosition.x, y: canvasSize.height - pad, width: movingSize.width, height: 3)))
        }
        if distLeft <= lineThreshold {
            hints.append(.edge(.left, CGRect(x: pad, y: movingPosition.y, width: 3, height: movingSize.height)))
        }
        if distRight <= lineThreshold {
            hints.append(.edge(.right, CGRect(x: canvasSize.width - pad, y: movingPosition.y, width: 3, height: movingSize.height)))
        }
        return hints
    }

    static func snappedToEdges(
        position: CGPoint,
        size: CGSize,
        canvasSize: CGSize
    ) -> CGPoint {
        let pad = canvasSidePadding
        let top = topCreationLimit
        let snapThreshold: CGFloat = 30

        var x = position.x
        var y = position.y

        let distToLeft = x - pad
        let distToRight = canvasSize.width - pad - x - size.width
        let distToTop = y - top
        let distToBottom = canvasSize.height - pad - y - size.height

        if distToLeft < snapThreshold {
            x = pad
        } else if distToRight < snapThreshold {
            x = canvasSize.width - pad - size.width
        }

        if distToTop < snapThreshold {
            y = top
        } else if distToBottom < snapThreshold {
            y = canvasSize.height - pad - size.height
        }

        return CGPoint(x: x, y: y)
    }
}
