import SwiftUI

/// Create/Confirm (и Change, если passcode уже существует) флоу для
/// Space Lock passcode. Секрет никогда не хранится здесь — сразу
/// уходит в PasscodeStore (Keychain) при успешном подтверждении.
/// Passcode — это 4 физические клавиши (см. KeyCodeCaptureView), можно
/// использовать буквы, а не только цифры; раскладка клавиатуры роли не
/// играет.
struct PasscodeSetupView: View {
    @Binding var isPresented: Bool
    var onComplete: (_ didSetPasscode: Bool) -> Void

    private enum Stage {
        case verifyCurrent
        case create
        case confirm
    }

    @State private var stage: Stage
    @State private var firstEntry: [UInt16] = []
    @State private var errorMessage: String?

    init(isPresented: Binding<Bool>, onComplete: @escaping (Bool) -> Void) {
        _isPresented = isPresented
        self.onComplete = onComplete
        _stage = State(initialValue: PasscodeStore.hasPasscode ? .verifyCurrent : .create)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))

            PasscodeDotsEntry { codes in handleSubmission(codes) }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Cancel") {
                isPresented = false
                onComplete(false)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 280)
    }

    private var title: String {
        switch stage {
        case .verifyCurrent: return "Enter Current Passcode"
        case .create: return "Create Passcode"
        case .confirm: return "Confirm Passcode"
        }
    }

    /// true — переход принят молча (следующая стадия или итоговый
    /// успех), false — отклонён с shake (неверный текущий код / коды не
    /// совпали / Keychain отказал), поле готово к повтору.
    private func handleSubmission(_ codes: [UInt16]) -> Bool {
        switch stage {
        case .verifyCurrent:
            guard PasscodeStore.verify(PasscodeEncoding.string(from: codes)) else {
                errorMessage = "Incorrect passcode."
                return false
            }
            errorMessage = nil
            stage = .create
            return true
        case .create:
            firstEntry = codes
            errorMessage = nil
            stage = .confirm
            return true
        case .confirm:
            guard codes == firstEntry else {
                errorMessage = "Passcodes didn't match. Try again."
                firstEntry = []
                stage = .create
                return false
            }
            guard PasscodeStore.set(PasscodeEncoding.string(from: codes)) else {
                // Keychain отказал в записи — НЕ сообщаем об успехе: иначе
                // isPasscodeEnabled стал бы true без реально сохранённого
                // кода, и пользователь остался бы заблокирован без
                // возможности разблокировать что-либо.
                errorMessage = "Couldn't save passcode. Try again."
                firstEntry = []
                stage = .create
                return false
            }
            isPresented = false
            onComplete(true)
            return true
        }
    }
}
