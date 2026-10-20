import Foundation
import Observation

/// Свой шаблон карточки: один файл `.thoughtstemplate` (JSON). Данные, не код —
/// так же, как будущие плагины (см. thoughts-plugins/docs/plugins.md). Приватность (Spoiler/Lock)
/// в шаблон не попадает.
struct UserTemplate: Codable, Equatable {
    static let formatIdentifier = "com.alxeu.thoughts.template"
    static let currentVersion = 1
    static let fileExtension = "thoughtstemplate"

    static let maxNameLength = 60
    static let maxNoteLength = 120
    static let maxTextLength = 100_000
    static let maxFileSize = 1_000_000
    /// Размер в клетках сетки (`k × 60 − 16` pt).
    static let gridRange = 2...24

    var format = UserTemplate.formatIdentifier
    var version = UserTemplate.currentVersion
    var name: String
    var note: String
    var text: String
    var columns: Int
    var rows: Int
    var tag: String?

    enum TemplateError: LocalizedError, Equatable {
        case notATemplate
        case unsupportedVersion(Int)
        case fileTooLarge
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .notATemplate: return "This file isn\u{2019}t a Thoughts template."
            case .unsupportedVersion: return "This template was made by a newer version of Thoughts. Update the app to use it."
            case .fileTooLarge: return "This file is too large to be a template."
            case .invalid(let reason): return "This template can\u{2019}t be used: \(reason)."
            }
        }
    }

    /// Разбор и проверка файла: формат, версия, длины и размеры. Неизвестный тег
    /// просто отбрасывается (шаблон из более новой версии не должен ломаться).
    static func decode(_ data: Data) throws -> UserTemplate {
        guard data.count <= maxFileSize else { throw TemplateError.fileTooLarge }
        guard var template = try? JSONDecoder().decode(UserTemplate.self, from: data),
              template.format == formatIdentifier else { throw TemplateError.notATemplate }
        guard template.version <= currentVersion else { throw TemplateError.unsupportedVersion(template.version) }

        template.name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        template.note = template.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.name.isEmpty, template.name.count <= maxNameLength else { throw TemplateError.invalid("the name is empty or too long") }
        guard template.note.count <= maxNoteLength else { throw TemplateError.invalid("the note is too long") }
        guard template.text.count <= maxTextLength else { throw TemplateError.invalid("the text is too long") }
        guard gridRange.contains(template.columns), gridRange.contains(template.rows) else { throw TemplateError.invalid("the size is out of range") }
        if let tag = template.tag, CardTagColor(rawValue: tag) == nil { template.tag = nil }
        return template
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Шаблон из существующей карточки: размер округляется до клеток сетки.
    init(name: String, note: String, text: String, size: CGSize, tag: CardTagColor?) {
        let step = BoardViewModel.cardSizeStep, gap = BoardViewModel.cardGap
        func cells(_ value: CGFloat) -> Int {
            min(max(Int(((value + gap) / step).rounded()), Self.gridRange.lowerBound), Self.gridRange.upperBound)
        }
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength))
        self.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNoteLength))
        self.text = text
        self.columns = cells(size.width)
        self.rows = cells(size.height)
        self.tag = tag?.rawValue
    }
}

/// Шаблон на диске.
struct StoredTemplate: Identifiable, Equatable {
    let url: URL
    let template: UserTemplate
    var id: String { url.lastPathComponent }
}

/// Папка своих шаблонов (`Templates/` рядом с доской; в Debug — своя, как у доски
/// и синка). Файлы — те же `.thoughtstemplate`, которыми делятся.
@Observable
final class UserTemplateStore {
    static let shared = UserTemplateStore()

    private let folder: URL
    private(set) var templates: [StoredTemplate] = []

    init(folder: URL? = nil) {
        self.folder = folder ?? BoardStore.dataFolder.appendingPathComponent("Templates", isDirectory: true)
        reload()
    }

    var folderURL: URL { folder }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        templates = urls
            .filter { $0.pathExtension == UserTemplate.fileExtension }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url), let template = try? UserTemplate.decode(data) else { return nil }
                return StoredTemplate(url: url, template: template)
            }
            .sorted { $0.template.name.localizedCaseInsensitiveCompare($1.template.name) == .orderedAscending }
    }

    /// Сохраняет под свободным именем файла («Name.thoughtstemplate», «Name 2…»).
    @discardableResult
    func add(_ template: UserTemplate) throws -> StoredTemplate {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = Self.fileName(for: template.name)
        var url = folder.appendingPathComponent(base).appendingPathExtension(UserTemplate.fileExtension)
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(index)").appendingPathExtension(UserTemplate.fileExtension)
            index += 1
        }
        try template.encoded().write(to: url, options: .atomic)
        reload()
        return StoredTemplate(url: url, template: template)
    }

    /// Импорт чужого файла: проверка и копия в папку шаблонов.
    @discardableResult
    func importFile(at url: URL) throws -> StoredTemplate {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= UserTemplate.maxFileSize else { throw UserTemplate.TemplateError.fileTooLarge }
        return try add(UserTemplate.decode(Data(contentsOf: url)))
    }

    func export(_ stored: StoredTemplate, to url: URL) throws {
        try stored.template.encoded().write(to: url, options: .atomic)
    }

    func delete(_ stored: StoredTemplate) {
        try? FileManager.default.removeItem(at: stored.url)
        reload()
    }

    /// Имя файла из имени шаблона: без разделителей путей и служебных символов.
    static func fileName(for name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Template" : String(cleaned.prefix(UserTemplate.maxNameLength))
    }
}

extension CardTemplate {
    init(_ stored: StoredTemplate) {
        let template = stored.template
        self.init(id: "user.\(stored.id)", name: template.name, note: template.note, text: template.text,
                  columns: template.columns, rows: template.rows, tag: template.tag.flatMap(CardTagColor.init(rawValue:)))
    }
}
