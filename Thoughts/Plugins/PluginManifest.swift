import AppKit

/// `manifest.json` пакета `.thoughtsplugin` — схема из thoughts-plugins/docs/plugins.md.
/// Плагин — только данные: шрифты, цвета, паттерны, темы и шаблоны карточек.
struct PluginManifest: Codable, Equatable {
    static let fileName = "manifest.json"
    static let packageExtension = "thoughtsplugin"
    static let supportedAPIVersions = 1...1

    var id: String
    var name: String
    var version: String
    var apiVersion: Int
    var minAppVersion: String?
    var author: String?
    var description: String?
    var homepage: String?
    /// Скрипт плагина (`main.js`) — нужен конвертерам. Без него плагин — только данные.
    var main: String?
    var permissions: Permissions?
    var contributes: Contributes?

    /// Права скрипта: пользователь видит их при установке и в списке плагинов.
    struct Permissions: Codable, Equatable {
        /// Хосты, к которым можно обращаться через `thoughts.fetch` (только https).
        var network: [String]?
    }

    var networkHosts: [String] { permissions?.network ?? [] }

    struct Contributes: Codable, Equatable {
        var fonts: [Font]?
        var textColors: [TextColor]?
        var patterns: [Pattern]?
        var themes: [Theme]?
        var cardTemplates: [Template]?
        var converters: [Converter]?
    }

    /// Конвертер строки (как в Spotlight): регистрируется скриптом через
    /// `thoughts.converter(id, { convert(line) })`.
    struct Converter: Codable, Equatable {
        var id: String
        var name: String
        var description: String?
    }

    struct Font: Codable, Equatable {
        var id: String
        var name: String
        /// Путь к .ttf/.otf внутри пакета.
        var file: String
        /// Имя семейства, под которым шрифт виден после регистрации.
        var family: String
    }

    struct TextColor: Codable, Equatable {
        var id: String
        var name: String
        var hex: String
    }

    struct Pattern: Codable, Equatable {
        var id: String
        var name: String
        /// dots, grid, lines, crosses, diagonal.
        var kind: String
        var spacing: Double?
        var lineWidth: Double?
        var dotSize: Double?
    }

    struct Theme: Codable, Equatable {
        var id: String
        var name: String
        /// Ссылки на элементы: `<pluginID>/<itemID>` этого пакета или встроенные `builtin.*`.
        var font: String?
        var textColor: String?
        var pattern: String?
        var patternIntensity: Double?
    }

    /// Шаблон карточки: либо один вариант (`text` + `size`), либо `variants` —
    /// тогда в правом клике это подменю (как встроенный Kanban).
    struct Template: Codable, Equatable {
        var id: String
        var name: String
        var note: String?
        var menuTitle: String?
        var text: String?
        var size: Size?
        var tag: String?
        var variants: [Variant]?
    }

    struct Variant: Codable, Equatable {
        var name: String
        var note: String?
        var text: String
        var size: Size
        var tag: String?
    }

    struct Size: Codable, Equatable {
        var columns: Int
        var rows: Int
    }

    /// Сколько элементов добавляет пакет — для списка в Settings.
    var itemCount: Int {
        guard let c = contributes else { return 0 }
        return (c.fonts?.count ?? 0) + (c.textColors?.count ?? 0) + (c.patterns?.count ?? 0)
            + (c.themes?.count ?? 0) + (c.cardTemplates?.count ?? 0) + (c.converters?.count ?? 0)
    }
}

enum PluginError: LocalizedError, Equatable {
    case notAPackage
    case badManifest(String)
    case unsupportedAPIVersion(Int)
    case needsNewerApp(String)
    case invalid(String)
    case alreadyInstalled(String)
    case unsigned

    var errorDescription: String? {
        switch self {
        case .notAPackage:
            return "This isn\u{2019}t a Thoughts plugin (a .thoughtsplugin folder with manifest.json)."
        case .badManifest(let reason):
            return "manifest.json can\u{2019}t be read: \(reason)."
        case .unsupportedAPIVersion(let version):
            return "This plugin uses plugin API \(version), which this version of Thoughts doesn\u{2019}t support."
        case .needsNewerApp(let version):
            return "This plugin needs Thoughts \(version) or later."
        case .invalid(let reason):
            return "This plugin can\u{2019}t be used: \(reason)."
        case .alreadyInstalled(let version):
            return "Version \(version) or newer of this plugin is already installed."
        case .unsigned:
            return "This plugin runs code and isn\u{2019}t from the Thoughts catalog. The App Store version of Thoughts installs only catalog plugins that run code."
        }
    }
}

/// Проверка пакета перед установкой и при каждом скане папки `Plugins/`: любая
/// ошибка отклоняет пакет целиком (правила — §4 дизайн-документа).
enum PluginValidator {
    static let maxPackageSize = 20_000_000
    static let maxFontSize = 10_000_000
    static let maxScriptSize = 1_000_000
    static let maxItemsPerPoint = 200
    static let maxVariants = 12
    static let allowedExtensions: Set<String> = ["json", "ttf", "otf", "js"]
    /// Файл подписи каталога (см. PluginSignature) — без расширения.
    static let signatureFileName = "signature"
    static let patternKinds: [String: CanvasPattern.Kind] = [
        "dots": .dots, "grid": .grid, "lines": .lines, "crosses": .crosses, "diagonal": .diagonal
    ]

    static func validate(packageAt url: URL, appVersion: String = Self.currentAppVersion,
                         requireSignatureForCode: Bool = PluginSignature.requiredForCode) throws -> PluginManifest {
        let root = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue,
              FileManager.default.fileExists(atPath: root.appendingPathComponent(PluginManifest.fileName).path) else {
            throw PluginError.notAPackage
        }

        try checkFiles(in: root)

        let data = try Data(contentsOf: root.appendingPathComponent(PluginManifest.fileName))
        let manifest: PluginManifest
        do {
            manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw PluginError.badManifest("missing \u{201C}\(key.stringValue)\u{201D}")
        } catch let DecodingError.typeMismatch(_, context) {
            throw PluginError.badManifest("wrong type at \u{201C}\(context.codingPath.map(\.stringValue).joined(separator: "."))\u{201D}")
        } catch {
            throw PluginError.badManifest("not valid JSON")
        }

        try checkHeader(manifest, appVersion: appVersion)
        try checkScript(manifest, root: root)
        if manifest.main != nil, requireSignatureForCode, !PluginSignature.isValid(packageAt: root) {
            throw PluginError.unsigned
        }
        try checkContributions(manifest, root: root)
        return manifest
    }

    static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // MARK: - Файлы пакета

    /// Только разрешённые типы, без симлинков и исполняемых, общий размер в лимите.
    private static func checkFiles(in root: URL) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey, .isExecutableKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
            throw PluginError.notAPackage
        }
        var total = 0
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: Set(keys))
            let name = file.lastPathComponent
            if values.isSymbolicLink == true { throw PluginError.invalid("\u{201C}\(name)\u{201D} is a link") }
            if values.isDirectory == true { continue }
            // Finder кладёт .DS_Store в любую открытую папку — не повод отклонять пакет.
            if name == ".DS_Store" || name == signatureFileName { continue }
            guard values.isRegularFile == true, allowedExtensions.contains(file.pathExtension.lowercased()) else {
                throw PluginError.invalid("\u{201C}\(name)\u{201D} isn\u{2019}t an allowed file type (.json, .ttf, .otf, .js)")
            }
            if values.isExecutable == true { throw PluginError.invalid("\u{201C}\(name)\u{201D} is executable") }
            total += values.fileSize ?? 0
            if total > maxPackageSize { throw PluginError.invalid("the package is larger than 20 MB") }
        }
    }

    // MARK: - Заголовок манифеста

    private static func checkHeader(_ m: PluginManifest, appVersion: String) throws {
        guard matches(m.id, #"^[a-z0-9.-]{3,100}$"#) else {
            throw PluginError.invalid("the id must be 3–100 characters: a–z, 0–9, dots and dashes")
        }
        try checkName(m.name, what: "plugin")
        guard matches(m.version, #"^\d+\.\d+\.\d+([-+][0-9A-Za-z.-]+)?$"#) else {
            throw PluginError.invalid("the version must look like 1.0.0")
        }
        guard PluginManifest.supportedAPIVersions.contains(m.apiVersion) else {
            throw PluginError.unsupportedAPIVersion(m.apiVersion)
        }
        if let minimum = m.minAppVersion, compareVersions(appVersion, minimum) == .orderedAscending {
            throw PluginError.needsNewerApp(minimum)
        }
        if let homepage = m.homepage {
            guard let url = URL(string: homepage), url.scheme == "https", url.host != nil else {
                throw PluginError.invalid("the homepage must be an https link")
            }
        }
    }

    // MARK: - Скрипт и права

    private static func checkScript(_ m: PluginManifest, root: URL) throws {
        let converters = m.contributes?.converters ?? []
        guard let main = m.main else {
            if !converters.isEmpty { throw PluginError.invalid("converters need a script: add \u{201C}main\u{201D}") }
            if !m.networkHosts.isEmpty { throw PluginError.invalid("network permissions need a script: add \u{201C}main\u{201D}") }
            return
        }
        let file = try fileInside(root, main, what: "main")
        guard file.pathExtension.lowercased() == "js" else { throw PluginError.invalid("\u{201C}main\u{201D} must be a .js file") }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxScriptSize else { throw PluginError.invalid("the script is larger than 1 MB") }
        for host in m.networkHosts {
            guard matches(host, #"^[a-z0-9-]+(\.[a-z0-9-]+)+$"#) else {
                throw PluginError.invalid("network permission \u{201C}\(host)\u{201D} must be a host name like api.example.com")
            }
        }
        try checkItems(converters.map(\.id), names: converters.map(\.name), point: "converters")
    }

    // MARK: - Точки расширения

    private static func checkContributions(_ m: PluginManifest, root: URL) throws {
        guard let c = m.contributes else { return }

        let fonts = c.fonts ?? []
        try checkItems(fonts.map(\.id), names: fonts.map(\.name), point: "fonts")
        for font in fonts {
            let file = try fileInside(root, font.file, what: "font \u{201C}\(font.id)\u{201D}")
            guard ["ttf", "otf"].contains(file.pathExtension.lowercased()) else {
                throw PluginError.invalid("font \u{201C}\(font.id)\u{201D} must be a .ttf or .otf file")
            }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= maxFontSize else { throw PluginError.invalid("font \u{201C}\(font.id)\u{201D} is larger than 10 MB") }
            guard !font.family.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw PluginError.invalid("font \u{201C}\(font.id)\u{201D} has no family name")
            }
        }

        let colors = c.textColors ?? []
        try checkItems(colors.map(\.id), names: colors.map(\.name), point: "textColors")
        for color in colors where !(color.hex.hasPrefix("#") && NSColor(hex: color.hex) != nil) {
            throw PluginError.invalid("text color \u{201C}\(color.id)\u{201D} must be #RRGGBB")
        }

        let patterns = c.patterns ?? []
        try checkItems(patterns.map(\.id), names: patterns.map(\.name), point: "patterns")
        for pattern in patterns {
            guard patternKinds[pattern.kind] != nil else {
                throw PluginError.invalid("pattern \u{201C}\(pattern.id)\u{201D} has an unknown kind \u{201C}\(pattern.kind)\u{201D}")
            }
            if let v = pattern.spacing, !(4...200).contains(v) { throw PluginError.invalid("pattern \u{201C}\(pattern.id)\u{201D}: spacing must be 4–200") }
            if let v = pattern.lineWidth, !(0.25...10).contains(v) { throw PluginError.invalid("pattern \u{201C}\(pattern.id)\u{201D}: lineWidth must be 0.25–10") }
            if let v = pattern.dotSize, !(0.5...20).contains(v) { throw PluginError.invalid("pattern \u{201C}\(pattern.id)\u{201D}: dotSize must be 0.5–20") }
        }

        let themes = c.themes ?? []
        try checkItems(themes.map(\.id), names: themes.map(\.name), point: "themes")
        let own = { (ids: [String]) in Set(ids.map { "\(m.id)/\($0)" }) }
        for theme in themes {
            try checkReference(theme.font, own: own(fonts.map(\.id)), builtIn: CardFontOption.builtIn.map(\.id), theme: theme.id, field: "font")
            try checkReference(theme.textColor, own: own(colors.map(\.id)), builtIn: TextColorOption.builtIn.map(\.id), theme: theme.id, field: "textColor")
            try checkReference(theme.pattern, own: own(patterns.map(\.id)), builtIn: CanvasPattern.builtIn.map(\.id), theme: theme.id, field: "pattern")
            if let v = theme.patternIntensity, !AppearanceSettings.patternOpacityRange.contains(v) {
                throw PluginError.invalid("theme \u{201C}\(theme.id)\u{201D}: patternIntensity must be \(AppearanceSettings.patternOpacityRange.lowerBound)–\(AppearanceSettings.patternOpacityRange.upperBound)")
            }
        }

        let templates = c.cardTemplates ?? []
        try checkItems(templates.map(\.id), names: templates.map(\.name), point: "cardTemplates", maxName: UserTemplate.maxNameLength)
        for template in templates {
            if let variants = template.variants {
                guard (1...maxVariants).contains(variants.count) else {
                    throw PluginError.invalid("template \u{201C}\(template.id)\u{201D} must have 1–\(maxVariants) variants")
                }
                for variant in variants {
                    try checkName(variant.name, what: "a variant of \u{201C}\(template.id)\u{201D}", max: UserTemplate.maxNameLength)
                    try checkTemplateBody(text: variant.text, size: variant.size, tag: variant.tag, id: template.id)
                }
            } else {
                guard let text = template.text, let size = template.size else {
                    throw PluginError.invalid("template \u{201C}\(template.id)\u{201D} needs text and size, or variants")
                }
                try checkTemplateBody(text: text, size: size, tag: template.tag, id: template.id)
            }
        }
    }

    private static func checkTemplateBody(text: String, size: PluginManifest.Size, tag: String?, id: String) throws {
        guard text.count <= UserTemplate.maxTextLength else { throw PluginError.invalid("template \u{201C}\(id)\u{201D} text is too long") }
        guard UserTemplate.gridRange.contains(size.columns), UserTemplate.gridRange.contains(size.rows) else {
            throw PluginError.invalid("template \u{201C}\(id)\u{201D} size must be \(UserTemplate.gridRange.lowerBound)–\(UserTemplate.gridRange.upperBound) tiles")
        }
        if let tag, CardTagColor(rawValue: tag) == nil {
            throw PluginError.invalid("template \u{201C}\(id)\u{201D} has an unknown tag \u{201C}\(tag)\u{201D}")
        }
    }

    private static func checkItems(_ ids: [String], names: [String], point: String, maxName: Int = 40) throws {
        guard ids.count <= maxItemsPerPoint else { throw PluginError.invalid("\(point) has more than \(maxItemsPerPoint) items") }
        var seen = Set<String>()
        for id in ids {
            guard matches(id, #"^[a-z0-9-]{1,60}$"#) else {
                throw PluginError.invalid("\(point) id \u{201C}\(id)\u{201D} may use only a–z, 0–9 and dashes")
            }
            guard seen.insert(id).inserted else { throw PluginError.invalid("\(point) id \u{201C}\(id)\u{201D} is used twice") }
        }
        for name in names { try checkName(name, what: "an item in \(point)", max: maxName) }
    }

    private static func checkName(_ name: String, what: String, max: Int = 40) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= max else {
            throw PluginError.invalid("the name of \(what) must be 1–\(max) characters")
        }
    }

    private static func checkReference(_ ref: String?, own: Set<String>, builtIn: [String], theme: String, field: String) throws {
        guard let ref else { return }
        guard own.contains(ref) || builtIn.contains(ref) else {
            throw PluginError.invalid("theme \u{201C}\(theme)\u{201D}: \(field) \u{201C}\(ref)\u{201D} doesn\u{2019}t exist")
        }
    }

    /// Путь из манифеста → файл внутри пакета (без `..` наружу и абсолютных путей).
    static func fileInside(_ root: URL, _ path: String, what: String) throws -> URL {
        let file = root.appendingPathComponent(path).standardizedFileURL
        guard !path.hasPrefix("/"), file.path.hasPrefix(root.path + "/"),
              FileManager.default.fileExists(atPath: file.path) else {
            throw PluginError.invalid("\(what): \u{201C}\(path)\u{201D} isn\u{2019}t a file inside the package")
        }
        return file
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    /// Сравнение версий по числовым компонентам: 1.10 > 1.9, 1.4 == 1.4.0.
    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        func parts(_ s: String) -> [Int] {
            s.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
