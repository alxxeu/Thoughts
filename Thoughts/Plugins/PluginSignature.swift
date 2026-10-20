import CryptoKit
import Foundation

/// Подпись плагинов с кодом. App Store-версия ставит плагин со скриптом, только если
/// он подписан ключом каталога (правило App Store 4.7: плагины на JavaScriptCore — из
/// своего проверенного каталога). DMG-версия ставит любые после подтверждения прав.
///
/// Формат (тот же в thoughts-plugins/scripts/sign-plugin.swift): все файлы пакета,
/// кроме `signature` и `.DS_Store`, по возрастанию относительного пути; сообщение —
/// строки `<путь>\n<sha256 файла hex>\n`; подпись Ed25519 над сообщением, base64 в
/// файле `signature` в корне пакета.
enum PluginSignature {
    /// Публичный ключ каталога, base64 (32 байта Curve25519). Пусто — ключа ещё нет:
    /// App Store-версия тогда не ставит плагины с кодом вовсе.
    static let catalogPublicKey = ""

    static var requiredForCode: Bool {
        #if DIRECT
        return false
        #else
        return true
        #endif
    }

    static func isValid(packageAt root: URL, publicKey: String = catalogPublicKey) -> Bool {
        guard let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let text = try? String(contentsOf: root.appendingPathComponent(PluginValidator.signatureFileName), encoding: .utf8),
              let signature = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let message = try? message(for: root) else { return false }
        return key.isValidSignature(signature, for: message)
    }

    /// Сообщение для подписи: пути и хэши всех файлов пакета.
    static func message(for root: URL) throws -> Data {
        let base = root.standardizedFileURL.path + "/"
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw PluginError.notAPackage
        }
        var entries: [(String, String)] = []
        for case let file as URL in enumerator {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let name = file.lastPathComponent
            if name == PluginValidator.signatureFileName || name == ".DS_Store" { continue }
            let path = String(file.standardizedFileURL.path.dropFirst(base.count))
            let hash = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
            entries.append((path, hash))
        }
        let text = entries.sorted { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }
            .map { "\($0.0)\n\($0.1)\n" }.joined()
        return Data(text.utf8)
    }
}
