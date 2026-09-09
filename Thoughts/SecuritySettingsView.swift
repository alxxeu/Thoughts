import SwiftUI

/// Таб Security в Settings. Passcode — обязательная база (как "Passcode
/// Lock" в Telegram): включение сразу запускает Create/Confirm passcode;
/// после этого открывается экран управления (Auto-Lock, Touch ID как
/// необязательная надстройка, список Space прямо здесь же, одним
/// прокручиваемым экраном — без отдельных подэкранов/шитов, чтобы не
/// плодить лишнюю навигацию).
struct SecuritySettingsTab: View {
    var viewModel: BoardViewModel

    private var settings: SecuritySettings { viewModel.securitySettings }

    @State private var isShowingPasscodeSetup = false
    // Различает, ЗАЧЕМ открыт один и тот же PasscodeSetupView-sheet: первое
    // включение Passcode Lock (тогда результат sheet'а — это и есть новое
    // значение isPasscodeEnabled) или смена уже существующего пароля через
    // "Change Passcode…" (тогда Passcode Lock уже включён и должен
    // оставаться включённым независимо от успеха/отмены — сам факт смены
    // пароля не должен трогать этот тумблер).
    @State private var isFirstTimePasscodeSetup = false
    @State private var isShowingDisableConfirmation = false
    @State private var pendingUnprotectSlot: Int?

    var body: some View {
        Form {
            if !settings.isPasscodeEnabled {
                Section {
                    Toggle("Passcode", isOn: passcodeEnabledBinding)
                        .toggleStyle(.switch)
                } footer: {
                    Text("Protect individual Spaces with a passcode lock screen. Turn a Space's lock on with Cmd+L or from the list below, once enabled here.")
                }
            } else {
                Section {
                    SettingsRowButton(title: "Turn Passcode Off") {
                        isShowingDisableConfirmation = true
                    }
                    SettingsRowButton(title: "Change Passcode…") {
                        isFirstTimePasscodeSetup = false
                        isShowingPasscodeSetup = true
                    }
                } footer: {
                    Text("When a Space is locked, unlock it with your passcode, or press Cmd+L to lock the current Space immediately.")
                }

                Section {
                    Picker("Auto-Lock", selection: Binding(
                        get: { settings.autoLockInterval },
                        set: { settings.autoLockInterval = $0 }
                    )) {
                        ForEach(AutoLockInterval.allCases) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }

                    Toggle("Use Touch ID", isOn: touchIDEnabledBinding)
                        .toggleStyle(.switch)
                }

                Section {
                    ForEach(viewModel.workspaces) { workspace in
                        Toggle(workspace.name, isOn: Binding(
                            get: { workspace.isProtected },
                            set: { newValue in
                                if newValue {
                                    viewModel.setSpaceProtected(true, slot: workspace.slot)
                                } else {
                                    // Выключение защиты конкретного Space —
                                    // тоже опасное действие, требует того же
                                    // подтверждения, что и полное выключение
                                    // Passcode целиком.
                                    pendingUnprotectSlot = workspace.slot
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                    }
                } header: {
                    Text("Manage Space Locks")
                } footer: {
                    Text("Locked Spaces require your passcode\(settings.isTouchIDEnabled ? " or Touch ID" : "") to open.")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isShowingPasscodeSetup) {
            PasscodeSetupView(isPresented: $isShowingPasscodeSetup) { didSetPasscode in
                // "Change Passcode…" (не первое включение) не должен
                // трогать isPasscodeEnabled вообще — ни при успехе (уже
                // true), ни при Cancel (должен остаться true, раньше здесь
                // был баг: Cancel тут ошибочно выключал Passcode Lock целиком).
                guard isFirstTimePasscodeSetup else { return }
                settings.isPasscodeEnabled = didSetPasscode
            }
        }
        .sheet(isPresented: $isShowingDisableConfirmation) {
            PasscodeConfirmView(
                isPresented: $isShowingDisableConfirmation,
                title: "Enter Passcode to Turn Off Passcode Lock",
                allowsTouchID: settings.isTouchIDEnabled,
                onTouchID: {
                    viewModel.authenticateWithTouchID { success in
                        if success {
                            isShowingDisableConfirmation = false
                            disablePasscode()
                        }
                    }
                }
            ) { success in
                if success { disablePasscode() }
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingUnprotectSlot != nil },
            set: { if !$0 { pendingUnprotectSlot = nil } }
        )) {
            if let slot = pendingUnprotectSlot {
                let workspaceName = viewModel.workspaces.first(where: { $0.slot == slot })?.name ?? Workspace.defaultName(forSlot: slot)
                PasscodeConfirmView(
                    isPresented: Binding(
                        get: { pendingUnprotectSlot != nil },
                        set: { if !$0 { pendingUnprotectSlot = nil } }
                    ),
                    title: "Enter Passcode to Unlock \u{201C}\(workspaceName)\u{201D}",
                    allowsTouchID: settings.isTouchIDEnabled,
                    onTouchID: {
                        viewModel.authenticateWithTouchID { success in
                            if success {
                                viewModel.setSpaceProtected(false, slot: slot)
                                pendingUnprotectSlot = nil
                            }
                        }
                    }
                ) { success in
                    if success {
                        viewModel.setSpaceProtected(false, slot: slot)
                    }
                    pendingUnprotectSlot = nil
                }
            }
        }
    }

    private var passcodeEnabledBinding: Binding<Bool> {
        // Этот Toggle рендерится только пока isPasscodeEnabled == false (см.
        // тело view выше), так что единственное реальное взаимодействие с
        // ним — включение; setter не нуждается в ветке на "выключить".
        Binding(
            get: { settings.isPasscodeEnabled },
            set: { _ in
                // Включение — не мгновенное: сначала обязательно создаём
                // код, тумблер визуально останется выключенным, пока сетап
                // не будет пройден до конца (или откатится при отмене).
                isFirstTimePasscodeSetup = true
                isShowingPasscodeSetup = true
            }
        )
    }

    private var touchIDEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isTouchIDEnabled },
            set: { newValue in
                guard newValue else {
                    settings.isTouchIDEnabled = false
                    return
                }
                // Включение требует реально пройти Touch ID прямо сейчас —
                // иначе можно было бы включить галку "на будущее", ни разу
                // не подтвердив, что Touch ID вообще настроен и работает.
                viewModel.authenticateWithTouchID { success in
                    if success {
                        settings.isTouchIDEnabled = true
                    }
                }
            }
        )
    }

    private func disablePasscode() {
        // Если Keychain отказал в удалении — не сообщаем UI, что Passcode
        // выключен: старый код остался бы в Keychain, а isPasscodeEnabled
        // ошибочно показывал бы "выключено".
        guard PasscodeStore.remove() else { return }
        settings.isPasscodeEnabled = false
        settings.isTouchIDEnabled = false
    }
}
