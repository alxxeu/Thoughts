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
    @State private var enteredCodes: [UInt16] = []
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

            ZStack {
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < enteredCodes.count ? Color.primary.opacity(0.85) : Color.primary.opacity(0.15))
                            .frame(width: 10, height: 10)
                    }
                }

                KeyCodeCaptureView(
                    onKeyCode: { code in appendCode(code) },
                    onDelete: { removeLastCode() }
                )
                .frame(width: 1, height: 1)
            }

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

    private func appendCode(_ code: UInt16) {
        guard enteredCodes.count < 4 else { return }
        enteredCodes.append(code)
        guard enteredCodes.count == 4 else { return }

        switch stage {
        case .verifyCurrent:
            if PasscodeStore.verify(PasscodeEncoding.string(from: enteredCodes)) {
                errorMessage = nil
                enteredCodes = []
                stage = .create
            } else {
                errorMessage = "Incorrect passcode."
                enteredCodes = []
            }
        case .create:
            firstEntry = enteredCodes
            errorMessage = nil
            enteredCodes = []
            stage = .confirm
        case .confirm:
            if enteredCodes == firstEntry {
                PasscodeStore.set(PasscodeEncoding.string(from: enteredCodes))
                isPresented = false
                onComplete(true)
            } else {
                errorMessage = "Passcodes didn't match. Try again."
                firstEntry = []
                enteredCodes = []
                stage = .create
            }
        }
    }

    private func removeLastCode() {
        guard !enteredCodes.isEmpty else { return }
        enteredCodes.removeLast()
    }
}
