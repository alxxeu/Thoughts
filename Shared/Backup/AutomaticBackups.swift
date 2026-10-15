import Foundation

/// Страховочные копии перед необратимыми операциями (импорт с заменой,
/// первое включение синка) — в `Application Support/Thoughts/Backups`,
/// рядом с самим board.json. Хранятся последние `keepCount`, более старые
/// удаляются.
///
/// Не шифруются: лежат в том же sandbox-контейнере, что и открытый
/// board.json, — пароль здесь ничего бы не добавил.
enum AutomaticBackups {
    private static let keepCount = 10

    static var folder: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Thoughts", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }

    /// - Parameter reason: короткий префикс имени файла, напр. "before-import".
    @discardableResult
    static func write(_ snapshot: BoardSnapshot, reason: String, now: Date = Date()) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = folder.appendingPathComponent("\(reason)-\(formatter.string(from: now)).\(BackupCodec.fileExtension)")

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try BackupCodec.encode(snapshot, password: nil, now: now).write(to: url, options: .atomic)
        } catch {
            print("Automatic backup failed: \(error)")
            return nil
        }
        pruneOldBackups()
        return url
    }

    private static func pruneOldBackups() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        let backups = files
            .filter { $0.pathExtension == BackupCodec.fileExtension }
            .sorted { creationDate($0) > creationDate($1) }
        for url in backups.dropFirst(keepCount) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func creationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }
}
