import SwiftUI

/// Полноэкранная (на весь Space) версия существующего lock/spoiler
/// оверлея заметки — то же звёздное поле (StarFieldCanvas), тот же
/// визуальный язык. Passcode — всегда обязательная база; кнопка Touch ID
/// появляется под ним только если он включён в настройках (см.
/// SecuritySettings.isTouchIDEnabled). Никакого "tap to unlock" — раз
/// Space заблокирован, разблокировать можно только кодом или Touch ID.
struct SpaceLockOverlayView: View {
    var viewModel: BoardViewModel

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
    }

    // MARK: - Passcode

    /// .id(activeSlot) — переключение на другой (тоже заблокированный)
    /// Space должно сбросить попытку разблокировки предыдущего; смена id
    /// пересоздаёт PasscodeDotsEntry с нуля вместо явного .onChange-сброса.
    private var passcodeEntry: some View {
        PasscodeDotsEntry { codes in
            guard PasscodeStore.verify(PasscodeEncoding.string(from: codes)) else { return false }
            viewModel.unlockActiveSpace()
            return true
        }
        .padding(.horizontal, 4)
        .id(viewModel.activeSlot)
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
