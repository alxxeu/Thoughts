import Foundation
import Security

/// Хранит 4-значный passcode для Space Lock в Keychain — никогда в
/// UserDefaults/JSON/plaintext. Keychain уже шифрует данные на диске и
/// привязан к учётке пользователя, поэтому хранить сам код (а не хэш)
/// здесь допустимо и проще.
enum PasscodeStore {
    /// При включённом синке с iCloud код ещё и в iCloud Keychain — один
    /// passcode на всех Mac пользователя (см. SyncableKeychainItem).
    static let item = SyncableKeychainItem(service: "com.alxeu.Thoughts.spacelock", account: "space-lock-passcode")

    static var hasPasscode: Bool {
        item.read() != nil
    }

    /// Возвращает false при неудаче записи в Keychain — вызывающая сторона
    /// не должна считать passcode сохранённым, если это не так (иначе
    /// isPasscodeEnabled=true при фактически несохранённом коде намертво
    /// заблокирует пользователя от собственных карточек).
    @discardableResult
    static func set(_ passcode: String) -> Bool {
        item.write(passcode)
    }

    static func verify(_ passcode: String) -> Bool {
        guard let stored = item.read() else { return false }
        return stored == passcode
    }

    /// errSecItemNotFound тоже считается успехом — конечное состояние
    /// ("код отсутствует в Keychain"), к которому стремится этот вызов,
    /// уже достигнуто.
    @discardableResult
    static func remove() -> Bool {
        item.remove()
    }
}
