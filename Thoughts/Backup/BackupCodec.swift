import Foundation
import CryptoKit
import CommonCrypto
import UniformTypeIdentifiers

/// Файл бэкапа `.thoughtsbackup` — JSON-конверт с версией формата и либо
/// открытым снимком доски (`payload`), либо зашифрованным (`ciphertext`).
///
/// Шифрование — AES-GCM-256 (CryptoKit), ключ выводится из пароля через
/// PBKDF2-SHA256. GCM заодно проверяет целостность: неверный пароль и
/// повреждённый файл одинаково не расшифровываются, вместо мусора.
enum BackupCodec {
    static let formatIdentifier = "com.alxeu.thoughts.backup"
    static let currentVersion = 1
    static let minimumPasswordLength = 8
    /// Защита от случайно выбранного огромного файла — реальные бэкапы
    /// на порядки меньше.
    static let maximumFileSize = 200 * 1024 * 1024

    static let fileExtension = "thoughtsbackup"
    /// Тип только по расширению (conforms to public.data), без "conformingTo:
    /// .json": тип объявлен динамически, и файл на диске система определяет
    /// именно так. С conformingTo получался другой dyn-идентификатор, и уже
    /// сохранённые бэкапы были серыми в окне импорта.
    static var contentType: UTType {
        UTType(filenameExtension: fileExtension) ?? .data
    }

    struct Envelope: Codable {
        var format: String
        var version: Int
        var createdAt: Date
        var appVersion: String
        var encryption: EncryptionInfo?
        var payload: BoardSnapshot?
        var ciphertext: Data?

        var isEncrypted: Bool { encryption != nil }
    }

    struct EncryptionInfo: Codable {
        var algorithm = "AES-GCM-256"
        var kdf = "PBKDF2-SHA256"
        var iterations: Int
        var salt: Data
    }

    enum BackupError: LocalizedError, Equatable {
        case notABackup
        case unsupportedVersion(Int)
        case fileTooLarge
        case passwordRequired
        case wrongPassword
        case corrupted

        var errorDescription: String? {
            switch self {
            case .notABackup: return "This file isn\u{2019}t a Thoughts backup."
            case .unsupportedVersion: return "This backup was made by a newer version of Thoughts. Update the app to import it."
            case .fileTooLarge: return "This file is too large to be a Thoughts backup."
            case .passwordRequired: return "This backup is protected with a password."
            case .wrongPassword: return "The password is incorrect, or the backup is damaged."
            case .corrupted: return "This backup is damaged and can\u{2019}t be read."
            }
        }
    }

    /// 600k итераций — рекомендация OWASP для PBKDF2-SHA256: на Apple
    /// Silicon это доли секунды для одного вывода ключа, но делает перебор
    /// паролей по украденному файлу дорогим.
    private static let kdfIterations = 600_000

    // MARK: - Encode

    static func encode(_ snapshot: BoardSnapshot, password: String?, now: Date = Date()) throws -> Data {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        var envelope = Envelope(
            format: formatIdentifier,
            version: currentVersion,
            createdAt: now,
            appVersion: appVersion,
            encryption: nil,
            payload: snapshot,
            ciphertext: nil
        )

        if let password {
            let salt = randomBytes(count: 16)
            let key = try deriveKey(password: password, salt: salt, iterations: kdfIterations)
            let plaintext = try makeEncoder().encode(snapshot)
            guard let sealed = try AES.GCM.seal(plaintext, using: key).combined else { throw BackupError.corrupted }
            envelope.encryption = EncryptionInfo(iterations: kdfIterations, salt: salt)
            envelope.payload = nil
            envelope.ciphertext = sealed
        }

        return try makeEncoder().encode(envelope)
    }

    // MARK: - Decode

    /// Разбирает конверт без расшифровки — чтобы понять, нужен ли пароль.
    static func inspect(_ data: Data) throws -> Envelope {
        guard data.count <= maximumFileSize else { throw BackupError.fileTooLarge }
        guard let envelope = try? makeDecoder().decode(Envelope.self, from: data),
              envelope.format == formatIdentifier else {
            throw BackupError.notABackup
        }
        guard envelope.version <= currentVersion else {
            throw BackupError.unsupportedVersion(envelope.version)
        }
        return envelope
    }

    static func decode(_ data: Data, password: String?) throws -> BoardSnapshot {
        let envelope = try inspect(data)

        guard let encryption = envelope.encryption else {
            guard let payload = envelope.payload else { throw BackupError.corrupted }
            return sanitized(payload)
        }

        guard let password else { throw BackupError.passwordRequired }
        guard let ciphertext = envelope.ciphertext,
              encryption.iterations > 0, encryption.iterations <= 10_000_000 else {
            throw BackupError.corrupted
        }
        let key = try deriveKey(password: password, salt: encryption.salt, iterations: encryption.iterations)
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: ciphertext), using: key)
        } catch {
            throw BackupError.wrongPassword
        }
        guard let snapshot = try? makeDecoder().decode(BoardSnapshot.self, from: plaintext) else {
            throw BackupError.corrupted
        }
        return sanitized(snapshot)
    }

    /// Файл пришёл снаружи — отбрасываем то, что приложение физически не
    /// сможет показать: Spaces вне 1–9, дубли, нечисловую геометрию.
    private static func sanitized(_ snapshot: BoardSnapshot) -> BoardSnapshot {
        var seenSlots = Set<Int>()
        let workspaces = snapshot.workspaces.filter { (1...9).contains($0.slot) && seenSlots.insert($0.slot).inserted }

        var seenIDs = Set<UUID>()
        let cards = snapshot.cards.compactMap { card -> CardRecord? in
            guard (1...9).contains(card.workspaceSlot), seenIDs.insert(card.id).inserted else { return nil }
            let numbers = [card.x, card.y, card.width, card.height]
            guard numbers.allSatisfy(\.isFinite) else { return nil }
            var card = card
            card.width = max(card.width, BoardViewModel.minCardSize)
            card.height = max(card.height, BoardViewModel.minCardSize)
            return card
        }
        return BoardSnapshot(workspaces: workspaces, cards: cards)
    }

    // MARK: - Helpers

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFormatter.string(from: date))
        }
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = isoFormatter.date(from: string) ?? ISO8601DateFormatter().date(from: string) {
                return date
            }
            throw BackupError.corrupted
        }
        return decoder
    }

    /// С долями секунды: иначе при слиянии две правки в пределах одной
    /// секунды выглядели бы одновременными.
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes)
    }

    private static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let passwordData = Data(password.precomposedStringWithCanonicalMapping.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = passwordData.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                    passwordData.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &derived,
                    derived.count
                )
            }
        }
        guard status == kCCSuccess else { throw BackupError.corrupted }
        return SymmetricKey(data: derived)
    }
}
