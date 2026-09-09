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

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)

            PasscodeDotsEntry { codes in
                guard PasscodeStore.verify(PasscodeEncoding.string(from: codes)) else {
                    errorMessage = "Incorrect passcode."
                    return false
                }
                isPresented = false
                onResult(true)
                return true
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
}
