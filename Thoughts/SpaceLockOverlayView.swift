import SwiftUI

/// Полноэкранная (на весь Space) версия существующего lock/spoiler
/// оверлея заметки — то же звёздное поле (StarFieldCanvas), тот же
/// визуальный язык. Passcode — всегда обязательная база; кнопка Touch ID
/// появляется под ним только если он включён в настройках (см.
/// SecuritySettings.isTouchIDEnabled). Никакого "tap to unlock" — раз
/// Space заблокирован, разблокировать можно только кодом или Touch ID.
struct SpaceLockOverlayView: View {
    var viewModel: BoardViewModel

    @State private var enteredCodes: [UInt16] = []
    @State private var shakeOffsetX: CGFloat = 0

    var body: some View {
        ZStack {
            Group {
                if #available(macOS 26.0, *) {
                    Rectangle()
                        .fill(Color.black.opacity(0.1))
                        .glassEffect(in: .rect)
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Rectangle().fill(Color.black.opacity(0.1)))
                }
            }
            .ignoresSafeArea()

            StarFieldCanvas()
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .shadow(color: .black.opacity(0.5), radius: 4)

                passcodeEntry

                if viewModel.securitySettings.isTouchIDEnabled {
                    touchIDButton
                }
            }
        }
        .contentShape(Rectangle())
        .onChange(of: viewModel.activeSlot) { _, _ in
            // Переход на другой (тоже заблокированный) Space — сбрасываем
            // локальное состояние попытки разблокировки предыдущего.
            enteredCodes = []
        }
    }

    // MARK: - Passcode

    private var passcodeEntry: some View {
        ZStack {
            HStack(spacing: 14) {
                ForEach(0..<PasscodeEncoding.length, id: \.self) { index in
                    Circle()
                        .fill(index < enteredCodes.count ? Color.primary.opacity(0.85) : Color.primary.opacity(0.15))
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.horizontal, 4)
            .offset(x: shakeOffsetX)

            KeyCodeCaptureView(
                onKeyCode: { code in appendCode(code) },
                onDelete: { removeLastCode() }
            )
            .frame(width: 1, height: 1)
        }
    }

    private func appendCode(_ code: UInt16) {
        guard enteredCodes.count < PasscodeEncoding.length else { return }
        enteredCodes.append(code)
        guard enteredCodes.count == PasscodeEncoding.length else { return }

        if PasscodeStore.verify(PasscodeEncoding.string(from: enteredCodes)) {
            viewModel.unlockActiveSpace()
        } else {
            triggerShake()
            enteredCodes = []
        }
    }

    private func removeLastCode() {
        guard !enteredCodes.isEmpty else { return }
        enteredCodes.removeLast()
    }

    /// Быстрая многократная тряска вместо одиночного плавного сдвига —
    /// большая амплитуда, короткие шаги.
    private func triggerShake() {
        let bounces: [CGFloat] = [-14, 14, -10, 10, -6, 6, 0]
        for (index, value) in bounces.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.045) {
                withAnimation(.easeInOut(duration: 0.045)) {
                    shakeOffsetX = value
                }
            }
        }
    }

    // MARK: - Touch ID

    private var touchIDButton: some View {
        Button {
            triggerTouchID()
        } label: {
            Text("Unlock with Touch ID")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func triggerTouchID() {
        viewModel.authenticateWithTouchID { success in
            if success {
                viewModel.unlockActiveSpace()
            }
        }
    }
}
