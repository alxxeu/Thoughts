import CloudKit

/// Служебное состояние синка на диске, рядом с board.json:
/// - сериализация CKSyncEngine (что уже скачано, что ждёт отправки);
/// - системные поля каждой записи (change tag) — без них сервер считал бы
///   каждую правку созданием новой записи и отвечал конфликтом.
///
/// Всё это — только кэш: удаление папки означает "синк с нуля" (при
/// следующем включении снова спросим Merge / Use iCloud / Use This Mac).
final class SyncStateStore {
    private let folder: URL
    private var stateURL: URL { folder.appendingPathComponent("engine-state.json") }
    private var recordsURL: URL { folder.appendingPathComponent("record-system-fields.plist") }

    private var systemFields: [String: Data] = [:]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        folder = appSupport.appendingPathComponent("Thoughts/Sync", isDirectory: true)
        if let data = try? Data(contentsOf: recordsURL),
           let decoded = try? PropertyListDecoder().decode([String: Data].self, from: data) {
            systemFields = decoded
        }
    }

    // MARK: - Engine state

    func loadEngineState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    func saveEngineState(_ state: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        write(data, to: stateURL)
    }

    // MARK: - Record system fields

    /// Пустая запись с системными полями последней известной серверной
    /// версии — на неё накладываются актуальные значения полей.
    func lastKnownRecord(for recordID: CKRecord.ID) -> CKRecord? {
        guard let data = systemFields[recordID.recordName] else { return nil }
        let coder: NSKeyedUnarchiver
        do {
            coder = try NSKeyedUnarchiver(forReadingFrom: data)
        } catch {
            return nil
        }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    func remember(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        systemFields[record.recordID.recordName] = coder.encodedData
        persistSystemFields()
    }

    func forget(_ recordID: CKRecord.ID) {
        guard systemFields.removeValue(forKey: recordID.recordName) != nil else { return }
        persistSystemFields()
    }

    /// Полный сброс — выключение синка, смена/выход из аккаунта, удаление
    /// данных в iCloud.
    func reset() {
        systemFields = [:]
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Private

    private func persistSystemFields() {
        guard let data = try? PropertyListEncoder().encode(systemFields) else { return }
        write(data, to: recordsURL)
    }

    private func write(_ data: Data, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            print("iCloud sync: couldn't write \(url.lastPathComponent): \(error)")
        }
    }
}
