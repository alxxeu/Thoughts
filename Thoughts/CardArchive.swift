import Foundation

/// Удалённая карточка в архиве: снимок записи + когда и из какого Space.
struct ArchivedCard: Codable, Identifiable, Equatable {
    var record: CardRecord
    var archivedAt: Date
    var id: UUID { record.id }
    var slot: Int { record.workspaceSlot }
}

/// Архив удалённых карточек (hold-to-delete и Clear Space): хранится 30 дней, потом
/// стирается сам; оттуда карточку можно вернуть в её Space или удалить насовсем.
/// shortcut: архив только локальный (файл archive.json рядом с board.json), в iCloud-синк
/// и бэкапы не входит; когда понадобится на нескольких Mac — завести CloudKit-запись.
@Observable
final class CardArchive {
    static let retention: TimeInterval = 30 * 24 * 3600

    private(set) var items: [ArchivedCard] = []
    @ObservationIgnored private let fileURL: URL?

    /// `fileURL` nil — архив только в памяти (тесты).
    init(fileURL: URL? = CardArchive.defaultURL, now: Date = Date()) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([ArchivedCard].self, from: data) {
            items = decoded
        }
        purgeExpired(now: now)
    }

    private static var defaultURL: URL {
        try? FileManager.default.createDirectory(at: BoardStore.dataFolder, withIntermediateDirectories: true)
        return BoardStore.dataFolder.appendingPathComponent(DemoMode.isActive ? "demo-archive.json" : "archive.json")
    }

    func add(_ cards: [Card], slot: Int, now: Date = Date()) {
        guard !cards.isEmpty else { return }
        items.insert(contentsOf: cards.map { ArchivedCard(record: CardRecord($0, slot: slot), archivedAt: now) }, at: 0)
        purgeExpired(now: now)
        save()
    }

    /// Убирает карточку из архива и отдаёт запись для возврата на доску.
    func take(_ id: UUID) -> CardRecord? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = items.remove(at: index)
        save()
        return item.record
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func removeAll() {
        items = []
        save()
    }

    func daysLeft(_ item: ArchivedCard, now: Date = Date()) -> Int {
        max(0, Int((item.archivedAt.addingTimeInterval(Self.retention).timeIntervalSince(now) / 86400).rounded(.up)))
    }

    private func purgeExpired(now: Date) {
        let before = items.count
        items.removeAll { now.timeIntervalSince($0.archivedAt) > Self.retention }
        if items.count != before { save() }
    }

    /// Запись — в фоне (последовательная очередь): синхронная запись на главном потоке сбивала
    /// анимацию исчезновения карточки при удалении.
    private static let writeQueue = DispatchQueue(label: "thoughts.archive.write", qos: .utility)

    /// Ждёт окончания фоновой записи (для тестов и завершения приложения).
    func flush() { Self.writeQueue.sync {} }

    private func save() {
        guard let fileURL else { return }
        let snapshot = items
        Self.writeQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
