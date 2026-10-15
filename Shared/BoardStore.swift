import Foundation
#if os(macOS)
import AppKit
#endif

private struct BoardData: Codable {
    var workspaces: [Workspace]
    var cardsByWorkspace: [Int: [Card]]
}

/// Только в Debug: запуск с `-demoBoard YES` — отдельная доска
/// demo-board.json для скриншотов и видео App Store, без iCloud и Spotlight,
/// чтобы демо-карточки не смешались с настоящими.
enum DemoMode {
    #if DEBUG
    static let isActive = UserDefaults.standard.bool(forKey: "demoBoard")
    #else
    static let isActive = false
    #endif
}

final class BoardStore {
    static let shared = BoardStore()

    private let fileURL: URL
    /// Куда отложен board.json, который не удалось прочитать при запуске, —
    /// AppDelegate показывает об этом алерт. nil, если всё прочиталось.
    private(set) var unreadableFileURL: URL?
    private var hasReportedSaveError = false

    /// Папка данных: доска, Sync/, Backups/. Debug ходит в Development-
    /// окружение CloudKit, App Store — в Production; общая папка смешала
    /// бы их доски и состояние синка.
    static let dataFolder: URL = {
        #if DEBUG
        let name = "Thoughts-Debug"
        #else
        let name = "Thoughts"
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(name, isDirectory: true)
    }()

    private convenience init() {
        let folder = Self.dataFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        self.init(fileURL: folder.appendingPathComponent(DemoMode.isActive ? "demo-board.json" : "board.json"))
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> (workspaces: [Workspace], cardsByWorkspace: [Int: [Card]]) {
        if let data = try? Data(contentsOf: fileURL) {
            if let decoded = try? JSONDecoder().decode(BoardData.self, from: data) {
                var workspaces = decoded.workspaces
                for slot in 1...9 where !workspaces.contains(where: { $0.slot == slot }) {
                    workspaces.append(Workspace(slot: slot, name: Workspace.defaultName(forSlot: slot)))
                }
                workspaces.sort { $0.slot < $1.slot }
                // Переведённое в Markdown сохраняем сразу (а не при первой
                // правке) — иначе каждый запуск без правок переводил бы файл
                // заново и оставлял ещё одну копию. Только если копия
                // исходника легла на диск.
                if decoded.cardsByWorkspace.values.joined().contains(where: \.wasMigratedToMarkdown),
                   keepCopyBeforeMarkdownMigration(data) {
                    save(workspaces: workspaces, cardsByWorkspace: decoded.cardsByWorkspace)
                }
                return (workspaces, decoded.cardsByWorkspace)
            }
            // Файл есть, но не читается (повреждён или записан более новой
            // версией) — откладываем его в сторону: иначе первое же сохранение
            // пустой доски перезаписало бы все карточки.
            setAsideUnreadableFile()
            return (defaultWorkspaces(), [:])
        }

        // Миграция со старой версии до появления Spaces (единый cards.json → Space 1)
        let legacyURL = fileURL.deletingLastPathComponent().appendingPathComponent("cards.json")
        if let legacyData = try? Data(contentsOf: legacyURL),
           let legacyCards = try? JSONDecoder().decode([Card].self, from: legacyData) {
            let workspaces = defaultWorkspaces()
            let cardsByWorkspace = [1: legacyCards]
            save(workspaces: workspaces, cardsByWorkspace: cardsByWorkspace)
            try? FileManager.default.removeItem(at: legacyURL)
            return (workspaces, cardsByWorkspace)
        }

        return (defaultWorkspaces(), [:])
    }

    func save(workspaces: [Workspace], cardsByWorkspace: [Int: [Card]]) {
        // Нечитаемый файл не удалось отложить — не затираем его.
        guard unreadableFileURL != fileURL else { return }
        let data = BoardData(workspaces: workspaces, cardsByWorkspace: cardsByWorkspace)
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            reportSaveError(error)
        }
    }

    /// Карточки старого формата при чтении уже переведены в Markdown (см.
    /// Card.init(from:)). Исходный файл — с архивами форматирования —
    /// сохраняется как есть: вернуть всё можно, просто переименовав копию.
    private func keepCopyBeforeMarkdownMigration(_ original: Data) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let folder = fileURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        let copy = folder.appendingPathComponent("before-markdown-\(formatter.string(from: Date())).json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try original.write(to: copy, options: .atomic)
            return true
        } catch {
            print("Couldn't keep a copy of board.json before the Markdown migration: \(error)")
            return false
        }
    }

    private func setAsideUnreadableFile() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let destination = fileURL.deletingLastPathComponent()
            .appendingPathComponent("board.unreadable-\(formatter.string(from: Date())).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
            unreadableFileURL = destination
        } catch {
            // Отложить не удалось — тогда хотя бы не даём перезаписать оригинал.
            print("Couldn't set aside unreadable board.json: \(error)")
            unreadableFileURL = fileURL
        }
    }

    /// Один алерт за сессию: при полном диске сохранение падает на каждой
    /// правке, и алерт на каждую был бы хуже молчания.
    private func reportSaveError(_ error: Error) {
        print("Couldn't save board.json: \(error)")
        guard !hasReportedSaveError else { return }
        hasReportedSaveError = true
        #if os(macOS)
        // shortcut: на iOS ошибка сохранения только в лог, алерт — с UI компаньона.
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Thoughts can\u{2019}t save your changes"
            alert.informativeText = error.localizedDescription
                + "\n\nCheck that your Mac has free disk space. Changes made since then may be lost if you quit."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        #endif
    }

    private func defaultWorkspaces() -> [Workspace] {
        (1...9).map { Workspace(slot: $0, name: Workspace.defaultName(forSlot: $0)) }
    }
}
