import CryptoKit
import Foundation
import Testing
@testable import Thoughts

@MainActor
struct ConverterServiceTests {
    private static let calculator = """
    thoughts.converter("calc", {
      convert(line) {
        if (!/^[\\d\\s.+\\-*/()]+$/.test(line) || !/\\d\\s*[+\\-*/]/.test(line)) return null
        return String(Function("return (" + line + ")")())
      }
    })
    thoughts.converter("slow", { convert(line) { if (line !== "spin") return null; var t = Date.now(); while (Date.now() - t < 1000) {} return "late" } })
    thoughts.converter("net", {
      async convert(line) {
        if (line !== "net") return null
        try { await thoughts.fetch("https://example.com/") } catch (e) { return "blocked" }
        return "fetched"
      }
    })
    """

    private func makeScript(_ source: String = calculator, hosts: [String] = []) throws -> PluginScript {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("script-\(UUID().uuidString).js")
        try Data(source.utf8).write(to: url)
        return PluginScript(pluginID: "com.test.calc", scriptURL: url, allowedHosts: hosts)
    }

    private func service(_ script: PluginScript, ids: [String]) -> ConverterService {
        let service = ConverterService()
        service.isEnabled = true
        service.converters = ids.map { ConverterEntry(script: script, id: $0, name: $0) }
        return service
    }

    private func ask(_ service: ConverterService, _ line: String) async -> String? {
        await withCheckedContinuation { continuation in
            service.request(line, debounce: .zero) { continuation.resume(returning: $0) }
        }
    }

    @Test func calculatorAnswersAndIgnoresText() async throws {
        let s = service(try makeScript(), ids: ["calc"])
        #expect(await ask(s, "12*3") == "36")
        #expect(await ask(s, "12*3 =") == "36")
        #expect(await ask(s, "buy milk") == nil)
    }

    @Test func registeredConverters() async throws {
        let script = try makeScript()
        let ids: [String] = await withCheckedContinuation { continuation in
            script.status { ids, _ in continuation.resume(returning: ids.sorted()) }
        }
        #expect(ids == ["calc", "net", "slow"])
    }

    @Test func slowConverterTimesOut() async throws {
        let s = service(try makeScript(), ids: ["slow"])
        // Отвечает через секунду — дольше 300 мс, ответ не принимается.
        #expect(await ask(s, "spin") == nil)
    }

    @Test func fetchOutsideDeclaredHostsIsRejected() async throws {
        let s = service(try makeScript(hosts: ["api.frankfurter.app"]), ids: ["net"])
        #expect(await ask(s, "net") == "blocked")
    }

    @Test func suffixFollowsWhatIsTyped() {
        #expect(ConverterService.suffix(for: "12*3", result: "36") == " = 36")
        #expect(ConverterService.suffix(for: "12*3 =", result: "36") == " 36")
        #expect(ConverterService.suffix(for: "12*3 = ", result: "36") == "36")
    }

    // MARK: - Подпись и проверка пакета со скриптом

    private func makePackage(main: Bool = true) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pkg-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Calc.thoughtsplugin", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let manifest = """
        { "id": "com.test.calc", "name": "Calc", "version": "1.0.0", "apiVersion": 1,
          \(main ? "\"main\": \"main.js\"," : "")
          "contributes": { "converters": [{ "id": "calc", "name": "Calculator" }] } }
        """
        try Data(manifest.utf8).write(to: url.appendingPathComponent("manifest.json"))
        try Data(Self.calculator.utf8).write(to: url.appendingPathComponent("main.js"))
        return url
    }

    @Test func convertersNeedAScript() throws {
        let url = try makePackage(main: false)
        #expect(throws: PluginError.self) { try PluginValidator.validate(packageAt: url, requireSignatureForCode: false) }
    }

    @Test func appStoreBuildNeedsCatalogSignature() throws {
        let url = try makePackage()
        #expect(throws: PluginError.unsigned) { try PluginValidator.validate(packageAt: url, requireSignatureForCode: true) }
        #expect(try PluginValidator.validate(packageAt: url, requireSignatureForCode: false).main == "main.js")
    }

    @Test func signatureCoversEveryFile() throws {
        let url = try makePackage()
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let signature = try key.signature(for: PluginSignature.message(for: url))
        try Data(signature.base64EncodedString().utf8).write(to: url.appendingPathComponent("signature"))
        #expect(PluginSignature.isValid(packageAt: url, publicKey: publicKey))

        // Любая правка после подписи — подпись недействительна.
        try Data("thoughts.converter('calc', { convert() { return 'x' } })".utf8).write(to: url.appendingPathComponent("main.js"))
        #expect(!PluginSignature.isValid(packageAt: url, publicKey: publicKey))
    }
}
