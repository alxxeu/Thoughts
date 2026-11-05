import Foundation
import Testing
@testable import Thoughts

@MainActor
struct PluginValidatorTests {
    private static let goodManifest = """
    {
      "id": "com.example.midnight",
      "name": "Midnight",
      "version": "1.0.0",
      "apiVersion": 1,
      "author": "Jane",
      "contributes": {
        "textColors": [{ "id": "moonlight", "name": "Moonlight", "hex": "#C8D3FF" }],
        "patterns": [{ "id": "fine-dots", "name": "Fine Dots", "kind": "dots", "spacing": 16, "dotSize": 1.5 }],
        "themes": [{ "id": "midnight", "name": "Midnight",
                     "textColor": "com.example.midnight/moonlight",
                     "pattern": "com.example.midnight/fine-dots", "patternIntensity": 0.15 }],
        "cardTemplates": [
          { "id": "standup", "name": "Daily Standup", "text": "Yesterday:\\n- ", "size": { "columns": 4, "rows": 4 }, "tag": "blue" },
          { "id": "week", "name": "Week", "menuTitle": "New Week Board",
            "variants": [{ "name": "5 Days", "text": "::: board\\n## Mon", "size": { "columns": 12, "rows": 6 } }] }
        ]
      }
    }
    """

    /// Временный пакет `<name>.thoughtsplugin` с manifest.json и доп. файлами.
    private func makePackage(manifest: String = goodManifest, files: [String: Data] = [:]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plugin-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Test.thoughtsplugin", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: url.appendingPathComponent("manifest.json"))
        for (path, data) in files {
            let file = url.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
        return url
    }

    private func manifest(replacing old: String, with new: String) -> String {
        Self.goodManifest.replacingOccurrences(of: old, with: new)
    }

    private func reason(_ manifest: String, files: [String: Data] = [:]) throws -> PluginError? {
        let url = try makePackage(manifest: manifest, files: files)
        do {
            _ = try PluginValidator.validate(packageAt: url, appVersion: "1.5")
            return nil
        } catch let error as PluginError {
            return error
        }
    }

    @Test func acceptsGoodPackage() throws {
        let url = try makePackage()
        let manifest = try PluginValidator.validate(packageAt: url, appVersion: "1.5")
        #expect(manifest.id == "com.example.midnight")
        #expect(manifest.itemCount == 5)
    }

    @Test func rejectsMissingManifestAndBadJSON() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(throws: PluginError.notAPackage) { try PluginValidator.validate(packageAt: folder) }
        #expect(try reason("{ not json") == .badManifest("not valid JSON"))
    }

    @Test func rejectsUnknownAPIAndNewerApp() throws {
        #expect(try reason(manifest(replacing: "\"apiVersion\": 1", with: "\"apiVersion\": 7")) == .unsupportedAPIVersion(7))
        #expect(try reason(manifest(replacing: "\"author\": \"Jane\"", with: "\"author\": \"Jane\", \"minAppVersion\": \"9.0\"")) == .needsNewerApp("9.0"))
    }

    @Test func rejectsBadHeaderValues() throws {
        #expect(try reason(manifest(replacing: "com.example.midnight\"", with: "Com Example\"")) != nil)
        #expect(try reason(manifest(replacing: "\"1.0.0\"", with: "\"one\"")) != nil)
        #expect(try reason(manifest(replacing: "\"author\": \"Jane\"", with: "\"author\": \"Jane\", \"homepage\": \"http://x.com\"")) != nil)
    }

    @Test func rejectsFilesOutsideAndForbiddenTypes() throws {
        let fontOutside = manifest(replacing: "\"textColors\"", with: """
        "fonts": [{ "id": "inter", "name": "Inter", "file": "../evil.ttf", "family": "Inter" }], "textColors"
        """)
        #expect(try reason(fontOutside) != nil)
        #expect(try reason(Self.goodManifest, files: ["run.sh": Data("echo".utf8)]) != nil)
    }

    @Test func rejectsSymlinks() throws {
        let url = try makePackage()
        try FileManager.default.createSymbolicLink(at: url.appendingPathComponent("link.json"),
                                                   withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        #expect(throws: PluginError.self) { try PluginValidator.validate(packageAt: url, appVersion: "1.5") }
    }

    @Test func rejectsBadItems() throws {
        #expect(try reason(manifest(replacing: "#C8D3FF", with: "blue")) != nil)
        #expect(try reason(manifest(replacing: "\"kind\": \"dots\"", with: "\"kind\": \"image\"")) != nil)
        #expect(try reason(manifest(replacing: "\"columns\": 4", with: "\"columns\": 99")) != nil)
        #expect(try reason(manifest(replacing: "\"tag\": \"blue\"", with: "\"tag\": \"pink\"")) != nil)
    }

    @Test func rejectsDanglingThemeReference() throws {
        #expect(try reason(manifest(replacing: "com.example.midnight/moonlight", with: "com.example.midnight/sunlight")) != nil)
        // Встроенные варианты в теме — можно.
        #expect(try reason(manifest(replacing: "com.example.midnight/moonlight", with: "builtin.amber")) == nil)
    }

    @Test func versionsCompareNumerically() {
        #expect(PluginValidator.compareVersions("1.10.0", "1.9.0") == .orderedDescending)
        #expect(PluginValidator.compareVersions("1.4", "1.4.0") == .orderedSame)
        #expect(PluginValidator.compareVersions("1.3", "1.4") == .orderedAscending)
    }

    @Test func managerInstallsTogglesAndRemoves() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plugins-\(UUID().uuidString)", isDirectory: true)
        let model = PluginsModel(folder: folder)
        let package = try makePackage()

        let plugin = try model.install(from: package)
        #expect(plugin.isEnabled)
        #expect(model.contributions.textColors.map(\.id) == ["com.example.midnight/moonlight"])
        #expect(model.contributions.templates.map(\.id) == ["com.example.midnight/standup", "com.example.midnight/week"])
        #expect(model.contributions.templates[1].variants.count == 1)

        // Та же версия ещё раз — отказ; выключили — вклад пропал.
        #expect(throws: PluginError.alreadyInstalled("1.0.0")) { try model.install(from: package) }
        model.setEnabled(false, for: plugin)
        #expect(model.contributions.textColors.isEmpty)
        model.setEnabled(true, for: plugin)

        model.remove(plugin)
        #expect(model.installed.isEmpty)
        #expect(model.contributions.themes.isEmpty)
    }
}
