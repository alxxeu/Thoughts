import SwiftUI

/// Полноэкранная (на весь Space) версия существующего lock/spoiler
/// оверлея заметки — то же звёздное поле (StarFieldCanvas), тот же
/// визуальный язык. Passcode — всегда обязательная база; кнопка Touch ID
/// появляется под ним только если он включён в настройках (см.
/// SecuritySettings.isTouchIDEnabled). Никакого "tap to unlock" — раз
/// Space заблокирован, разблокировать можно только кодом или Touch ID.
struct SpaceLockOverlayView: View {
    var viewModel: BoardViewModel
    @State private var isShowingNewPasscode = false

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

                // Раз в пару секунд — passcode может доехать через iCloud
                // Keychain, пока экран открыт (см. waitingForPasscode).
                TimelineView(.periodic(from: .now, by: 3)) { _ in
                    if PasscodeStore.hasPasscode {
                        passcodeEntry
                    } else {
                        waitingForPasscode
                    }
                }

                if viewModel.securitySettings.isTouchIDEnabled {
                    touchIDButton
                }
            }
        }
        .contentShape(Rectangle())
        .sheet(isPresented: $isShowingNewPasscode) {
            PasscodeSetupView(isPresented: $isShowingNewPasscode) { didSetPasscode in
                if didSetPasscode {
                    viewModel.securitySettings.isPasscodeEnabled = true
                }
            }
        }
    }

    // MARK: - Passcode not on this Mac yet

    /// Fail-closed: защищённый Space пришёл через iCloud раньше своего
    /// passcode (или iCloud Keychain выключен). Space остаётся закрытым;
    /// задать новый код можно только подтвердив, что это владелец Mac.
    private var waitingForPasscode: some View {
        VStack(spacing: 10) {
            Text("Waiting for your Space Lock passcode from iCloud Keychain\u{2026}")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Set New Passcode\u{2026}") {
                viewModel.authenticateWithTouchID(reason: "set a new Space Lock passcode") { success in
                    if success { isShowingNewPasscode = true }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: 280)
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
        viewModel.authenticateWithTouchID(reason: "unlock this Space") { success in
            if success {
                viewModel.unlockActiveSpace()
            }
        }
    }
}
