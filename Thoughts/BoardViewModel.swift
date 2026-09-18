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
    let desktopOverlay = DesktopOverlaySettings.shared
    let aiSettings = AISettings.shared

    /// Слоты защищённых (Workspace.isProtected == true) Space, прошедшие
    /// аутентификацию в ЭТОЙ сессии. Runtime-only, никогда не персистится:
    /// при старте приложения всегда пусто, поэтому любой защищённый Space
    /// стартует заблокированным. Отдельно от Workspace.isProtected —
    /// именно поэтому после успешной разблокировки Space "числится как
    /// имеющий блокировку", но при этом сейчас открыт.
    private var unlockedProtectedSlots: Set<Int> = []
    private var idleLockTasks: [Int: Task<Void, Never>] = [:]

    /// Карточки, созданные Ask AI/Summarize (Pro), которые ещё не были
    /// "активированы" явным кликом — см. CardView. Runtime-only, как
    /// unlockedProtectedSlots выше: не персистится и не переживает
    /// перезапуск приложения, но это ОК — постоянная подсветка нужна
    /// только для ориентации в текущей сессии.
    var aiHighlightedCardIDs: Set<UUID> = []

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

    /// Верхняя граница специально для Desktop Overlay — окно там растянуто
    /// на весь экран вплоть до самого верха (см. ContentView), и без
    /// отдельной, большей границы карточки могли бы создаваться/лежать
    /// вплотную к верхнему краю экрана (и под вырезом камеры). Ориентир —
    /// уровень, на котором обычно сидят системные виджеты рабочего стола:
    /// высота выреза (0 на моделях без него) плюс отступ.
    static var desktopOverlayTopInset: CGFloat {
        (NSScreen.main?.safeAreaInsets.top ?? 0) + 50
    }

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
        let clamped = min(9, max(1, slot))
        // Иначе зажатый хоткей (авто-повтор клавиши) на уже активном Space
        // непрерывно перезапускает переход/анимацию на то же самое место.
        guard clamped != activeSlot else { return }
        activeSlot = clamped
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

    /// Tidy Cards (Pro) — детерминированная построчная упаковка ("shelf
    /// packing"), без какого-либо AI: геометрия с наложениями — плохая
    /// задача для языковой модели, а сетка карточек и так уже квантована
    /// шагом cardSizeStep/cardGap, так что тут просто раскладка по рядам.
    /// Порядок — по текущей позиции (сверху-вниз, слева-направо), а не по
    /// порядку создания, чтобы не перемешивать то, что уже осмысленно
    /// разложено по строкам.
    private enum TidyQuadrant { case topLeft, topRight, bottomLeft, bottomRight }

    /// Раскладывает cardsToPack построчно ("shelf packing"), начиная от
    /// anchor и разрастаясь вдоль строки в сторону growRight/строк вниз в
    /// сторону growDown — так один и тот же алгоритм обслуживает все 4
    /// угла: для "исходящих от центра" углов growRight/growDown = false
    /// значит расти влево/вверх, а не вправо/вниз.
    private func packShelf(
        _ cardsToPack: [Card],
        anchor: CGPoint,
        growRight: Bool,
        growDown: Bool,
        maxRowExtent: CGFloat,
        gap: CGFloat
    ) {
        var alongAxis: CGFloat = 0
        var acrossAxis: CGFloat = 0
        var rowExtent: CGFloat = 0

        for card in cardsToPack {
            if alongAxis > 0, alongAxis + card.size.width > maxRowExtent {
                acrossAxis += rowExtent + gap
                alongAxis = 0
                rowExtent = 0
            }

            let x = growRight ? anchor.x + alongAxis : anchor.x - alongAxis - card.size.width
            let y = growDown ? anchor.y + acrossAxis : anchor.y - acrossAxis - card.size.height
            card.position = CGPoint(x: x, y: y)

            alongAxis += card.size.width + gap
            rowExtent = max(rowExtent, card.size.height)
        }
    }

    /// Tidy Cards (Pro) — детерминированная раскладка, без какого-либо AI
    /// (геометрия с наложениями — плохая задача для языковой модели, а
    /// сетка карточек и так уже квантована шагом cardSizeStep/cardGap).
    /// Карточки делятся на 4 группы по тому, в какой четверти канвы
    /// сейчас находится их центр (относительно центра канвы), и каждая
    /// группа стягивается к СВОЕМУ углу — а не все карточки в один общий
    /// поток от верхнего левого угла, из-за чего при широком окне всё
    /// раньше укладывалось в один длинный верхний ряд.
    func tidyCards(canvasSize: CGSize, topInset: CGFloat = topCreationLimit) {
        guard !cards.isEmpty else { return }

        let pad = Self.canvasSidePadding
        let gap = Self.cardGap
        let centerX = canvasSize.width / 2
        let centerY = (topInset + canvasSize.height) / 2
        let halfWidth = max(Self.minCardSize, centerX - pad)

        func quadrant(forCenter point: CGPoint) -> TidyQuadrant {
            switch (point.x < centerX, point.y < centerY) {
            case (true, true): return .topLeft
            case (false, true): return .topRight
            case (true, false): return .bottomLeft
            case (false, false): return .bottomRight
            }
        }

        func center(of card: Card) -> CGPoint {
            CGPoint(x: card.position.x + card.size.width / 2, y: card.position.y + card.size.height / 2)
        }

        // Шаг 1: у каждой карточки по умолчанию "родной" угол — тот же,
        // что и раньше, по её текущему положению относительно центра.
        var assignedQuadrant: [UUID: TidyQuadrant] = [:]
        for card in cards {
            assignedQuadrant[card.id] = quadrant(forCenter: center(of: card))
        }

        // Шаг 2: карточки с ОДИНАКОВЫМ тегом (если их 2+) ВСЕГДА стягиваются
        // в один угол — тот, где их и так сейчас больше всего (реальное
        // "скопление" тега). При ничьей по количеству явного скопления нет,
        // но угол всё равно нужен один — берём угол, в который попадает
        // центроид (средняя точка) всех карточек этого тега, а не оставляем
        // их разбросанными по своим родным углам.
        let taggedGroups = Dictionary(grouping: cards.filter { $0.tagColor != nil }) { $0.tagColor! }
        for (_, groupCards) in taggedGroups where groupCards.count > 1 {
            var counts: [TidyQuadrant: Int] = [:]
            for card in groupCards {
                counts[assignedQuadrant[card.id]!, default: 0] += 1
            }
            let maxCount = counts.values.max() ?? 0
            let winners = counts.filter { $0.value == maxCount }.map(\.key)

            let dominant: TidyQuadrant
            if winners.count == 1, let onlyWinner = winners.first {
                dominant = onlyWinner
            } else {
                let centers = groupCards.map(center(of:))
                let avgCenter = CGPoint(
                    x: centers.map(\.x).reduce(0, +) / CGFloat(centers.count),
                    y: centers.map(\.y).reduce(0, +) / CGFloat(centers.count)
                )
                dominant = quadrant(forCenter: avgCenter)
            }

            for card in groupCards {
                assignedQuadrant[card.id] = dominant
            }
        }

        // Внутри угла — сначала группируем по тегу (чтобы одинаковые
        // оказались физически рядом), внутри тега — обычный reading order.
        // Внутри тега — по убыванию площади: крупные карточки заполняют
        // угол первыми (то есть ближе к самому углу), а не вперемешку по
        // случайному исходному положению — так масштаб карточек сам
        // формирует что-то вроде masonry-раскладки, а не однородный ряд.
        func tidyOrder(_ a: Card, _ b: Card) -> Bool {
            let aTag = a.tagColor?.rawValue ?? ""
            let bTag = b.tagColor?.rawValue ?? ""
            if aTag != bTag { return aTag < bTag }
            return (a.size.width * a.size.height) > (b.size.width * b.size.height)
        }

        var groups: [TidyQuadrant: [Card]] = [:]
        for card in cards {
            groups[assignedQuadrant[card.id]!, default: []].append(card)
        }

        packShelf(
            (groups[.topLeft] ?? []).sorted(by: tidyOrder),
            anchor: CGPoint(x: pad, y: topInset), growRight: true, growDown: true,
            maxRowExtent: halfWidth, gap: gap
        )
        packShelf(
            (groups[.topRight] ?? []).sorted(by: tidyOrder),
            anchor: CGPoint(x: canvasSize.width - pad, y: topInset), growRight: false, growDown: true,
            maxRowExtent: halfWidth, gap: gap
        )
        packShelf(
            (groups[.bottomLeft] ?? []).sorted(by: tidyOrder),
            anchor: CGPoint(x: pad, y: canvasSize.height - pad), growRight: true, growDown: false,
            maxRowExtent: halfWidth, gap: gap
        )
        packShelf(
            (groups[.bottomRight] ?? []).sorted(by: tidyOrder),
            anchor: CGPoint(x: canvasSize.width - pad, y: canvasSize.height - pad), growRight: false, growDown: false,
            maxRowExtent: halfWidth, gap: gap
        )

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
        // No-op, если карточка уже последняя (то есть уже наверху) — вызовы
        // на каждый тик клика/драга не должны гонять лишнюю мутацию массива
        // с broadcast на весь ForEach, если z-порядок и так не меняется.
        guard let index = cards.firstIndex(where: { $0.id == card.id }), index != cards.count - 1 else { return }
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

    /// Для чистого перемещения/ресайза карточки (drag-end/resize-end) —
    /// текст, приватность и имя Space не менялись, так что Spotlight-индекс
    /// не может стать неактуальным и полную переиндексацию всех Spaces
    /// запускать не нужно.
    func saveGeometry() {
        saveTask?.cancel()
        saveTask = nil
        store.save(workspaces: workspaces, cardsByWorkspace: cardsByWorkspace)
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
    /// Единый размер карточки в Focus Mode — один и тот же для любой
    /// карточки, независимо от её реального `card.size` (см. ContentView:
    /// сам `card.size` при этом не меняется, фокус только переопределяет
    /// отображение).
    static let focusCardSize = CGSize(width: 640, height: 480)

    /// Под сфокусированной карточкой всегда висит кнопка "Ask AI…" — без
    /// этого резерва композиция "карточка + кнопка" читалась бы смещённой
    /// вниз, хотя сама карточка строго по центру.
    static let focusFooterReserve: CGFloat = 44

    /// Верхний левый угол сфокусированной карточки. При канве меньше
    /// самой карточки центрирование дало бы отрицательный origin и увело
    /// бы её верх/левый край за экран — поэтому зажимаем по тем же
    /// границам, что и обычные карточки.
    static func focusOrigin(canvasSize: CGSize, topInset: CGFloat = topCreationLimit) -> CGPoint {
        let availableHeight = canvasSize.height - topInset - focusFooterReserve
        return CGPoint(
            x: max(canvasSidePadding, (canvasSize.width - focusCardSize.width) / 2),
            y: max(topInset, topInset + (availableHeight - focusCardSize.height) / 2)
        )
    }

    static func placementPreview(
        movingId: UUID,
        movingPosition: CGPoint,
        movingSize: CGSize,
        others: [Card],
        canvasSize: CGSize,
        topInset: CGFloat = topCreationLimit
    ) -> CGPoint? {
        let gap = cardGap
        let activationDistance: CGFloat = 45
        let pad = canvasSidePadding
        let top = topInset
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
        canvasSize: CGSize,
        topInset: CGFloat = topCreationLimit
    ) -> [EdgeHint] {
        let pad = canvasSidePadding
        let top = topInset
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
        canvasSize: CGSize,
        topInset: CGFloat = topCreationLimit
    ) -> CGPoint {
        let pad = canvasSidePadding
        let top = topInset
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

    /// Не даёт точке/карточке (с size — .zero для точки без размера, как в
    /// жесте создания новой карточки) выйти за пределы канвы. Раньше было
    /// реализовано трижды по-разному: ContentView.adaptivePosition (только
    /// верхняя граница — для уже сохранённой позиции при показе),
    /// CardView.moveGesture (обе границы — во время драга) и
    /// ContentView.clamped (обе границы, без учёта размера — для точки
    /// драга создания). Здесь — одна функция с обеими границами и size,
    /// которая покрывает все три случая (size: .zero эквивалентен старому
    /// clamped).
    static func clampedPosition(_ point: CGPoint, size: CGSize, canvasSize: CGSize, topInset: CGFloat = topCreationLimit) -> CGPoint {
        let pad = canvasSidePadding
        let top = topInset
        let maxX = max(pad, canvasSize.width - pad - size.width)
        let maxY = max(top, canvasSize.height - pad - size.height)

        return CGPoint(
            x: min(maxX, max(pad, point.x)),
            y: min(maxY, max(top, point.y))
        )
    }
}
