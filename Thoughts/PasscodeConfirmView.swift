import SwiftUI

/// Разовая проверка passcode (с опциональной кнопкой Touch ID рядом) —
/// используется, когда нужно подтвердить личность перед опасным действием
/// (например, выключение Passcode целиком в Security Settings), в отличие
/// от PasscodeSetupView, который про создание/смену самого кода.
struct PasscodeConfirmView: View {
    @Binding var isPresented: Bool
    var title: String
    var allowsTouchID: Bool = false
    var onTouchID: (() -> Void)?
    var onResult: (Bool) -> Void

    @State private var enteredCodes: [UInt16] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)

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

            if allowsTouchID, let onTouchID {
                Button("Use Touch ID") {
                    onTouchID()
                }
                .buttonStyle(.bordered)
            }

            Button("Cancel") {
                isPresented = false
                onResult(false)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 280)
    }

    private func appendCode(_ code: UInt16) {
        guard enteredCodes.count < 4 else { return }
        enteredCodes.append(code)
        guard enteredCodes.count == 4 else { return }

        if PasscodeStore.verify(PasscodeEncoding.string(from: enteredCodes)) {
            isPresented = false
            onResult(true)
        } else {
            errorMessage = "Incorrect passcode."
            enteredCodes = []
        }
    }

    private func removeLastCode() {
        guard !enteredCodes.isEmpty else { return }
        enteredCodes.removeLast()
    }
}
