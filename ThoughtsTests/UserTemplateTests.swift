import Foundation
import Testing
@testable import Thoughts

@MainActor
struct UserTemplateTests {
    private func makeTemplate(name: String = "Daily plan") -> UserTemplate {
        UserTemplate(name: name, note: "mine", text: "::: board\n## Plan\n- ", size: CGSize(width: 584, height: 344), tag: .blue)
    }

    private func tempFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("templates-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func roundTrip() throws {
        let template = makeTemplate()
        #expect(try UserTemplate.decode(template.encoded()) == template)
        #expect(template.columns == 10 && template.rows == 6) // 584 pt, 344 pt
    }

    @Test func rejectsForeignAndFutureFiles() throws {
        #expect(throws: UserTemplate.TemplateError.notATemplate) { try UserTemplate.decode(Data("{}".utf8)) }
        #expect(throws: UserTemplate.TemplateError.notATemplate) { try UserTemplate.decode(Data("hello".utf8)) }
        var future = makeTemplate()
        future.version = 99
        #expect(throws: UserTemplate.TemplateError.unsupportedVersion(99)) { try UserTemplate.decode(future.encoded()) }
    }

    @Test func rejectsInvalidValues() throws {
        var noName = makeTemplate()
        noName.name = "  "
        #expect(throws: (any Error).self) { try UserTemplate.decode(noName.encoded()) }
        var huge = makeTemplate()
        huge.columns = 99
        #expect(throws: (any Error).self) { try UserTemplate.decode(huge.encoded()) }
        let big = Data(repeating: 0x20, count: UserTemplate.maxFileSize + 1)
        #expect(throws: UserTemplate.TemplateError.fileTooLarge) { try UserTemplate.decode(big) }
    }

    @Test func unknownTagIsDropped() throws {
        var template = makeTemplate()
        template.tag = "magenta"
        #expect(try UserTemplate.decode(template.encoded()).tag == nil)
    }

    @Test func storeAddsUniqueFilesAndDeletes() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = UserTemplateStore(folder: folder)
        let first = try store.add(makeTemplate())
        let second = try store.add(makeTemplate())
        #expect(first.url != second.url)
        #expect(store.templates.count == 2)
        store.delete(first)
        #expect(store.templates.count == 1)
        // Новый объект читает то, что лежит на диске.
        #expect(UserTemplateStore(folder: folder).templates.map(\.template.name) == ["Daily plan"])
    }

    @Test func importCopiesAValidFileAndRejectsGarbage() throws {
        let folder = tempFolder(), source = tempFolder()
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: source) }
        let store = UserTemplateStore(folder: folder)
        let good = source.appendingPathComponent("a.thoughtstemplate")
        try makeTemplate().encoded().write(to: good)
        #expect(try store.importFile(at: good).template.name == "Daily plan")
        let bad = source.appendingPathComponent("b.thoughtstemplate")
        try Data("nope".utf8).write(to: bad)
        #expect(throws: UserTemplate.TemplateError.notATemplate) { try store.importFile(at: bad) }
        #expect(store.templates.count == 1)
    }

    @Test func fileNamesAreSafe() {
        #expect(!UserTemplateStore.fileName(for: "../../etc/passwd").contains("/"))
        #expect(UserTemplateStore.fileName(for: "///") == "Template")
    }

    @Test func cardTemplateFromStored() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let stored = try UserTemplateStore(folder: folder).add(makeTemplate())
        let card = CardTemplate(stored)
        #expect(card.columns == 10 && card.tag == .blue)
        #expect(card.text.hasPrefix("::: board"))
    }
}
