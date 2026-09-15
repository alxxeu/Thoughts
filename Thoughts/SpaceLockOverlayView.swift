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
            // Тот же тёмный тон, что у карточек, но без настоящего
            // Liquid Glass — на весь экран (cornerRadius 0) он даёт
            // заметный блик-кромку по верхнему краю. См. CardSurfaceStyle.swift.
            CardSurfaceBackground(cornerRadius: 0, usesGlassEffect: false)
                .ignoresSafeArea()

            StarFieldCanvas()
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
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
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.12)))
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
