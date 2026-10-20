import SwiftUI

/// Плашка Space над канвой: имя (с переименованием по клику), действия
/// Ask AI / Tidy Cards / Clear Space и панель Ask AI по всему Space —
/// результат ответа появляется новой карточкой на канве.
struct SpaceToolbar: View {
    var viewModel: BoardViewModel
    var canvasSize: CGSize
    var topInset: CGFloat
    /// В Focus Mode плашка скрыта — открытая панель Ask AI закрывается,
    /// иначе она просто "вернулась" бы при выходе из фокуса.
    var isFocusModeActive: Bool
    /// Во время онбординга плашка What’s new ждёт.
    var isOnboardingActive: Bool

    @Environment(\.colorScheme) private var colorScheme
    /// Space, который сейчас переименовывают (nil — поле закрыто). Имя
    /// сохраняется именно в него, даже если пока печатали, Space сменился.
    @State private var renamingSlot: Int?
    @State private var workspaceNameDraft = ""
    @FocusState private var isWorkspaceNameFieldFocused: Bool

    // AI для всего Space — Ask AI под pill с названием. См. Thoughts/AI.
    // Результат — новая карточка на канве.
    @State private var isAskingSpaceAI = false
    @State private var spaceAIQuestion = ""
    @State private var isSpaceAIBusy = false
    @State private var spaceAIErrorMessage: String?
    /// Название функции, над иконкой которой сейчас курсор — управляет
    /// мгновенной подсветкой самой иконки.
    @State private var hoveredToolbarLabel: String?
    /// В отличие от hoveredToolbarLabel выше — не мгновенно: всплывающая
    /// подсказка под иконкой появляется только после небольшой задержки
    /// наведения (см. setToolbarHover), как обычные системные tooltips.
    @State private var tooltipVisibleLabel: String?
    @State private var tooltipTask: Task<Void, Never>?

    // Настройка капсулы: шестерёнка выплывает по наведению, режим правки («тряска»)
    // скрывает и возвращает иконки (SpaceToolbarSettings), пазл открывает панель Plugins.
    private let toolbarSettings = SpaceToolbarSettings.shared
    @State private var isEditingToolbar = false
    @State private var isHoveringPill = false
    @State private var isHoveringGear = false
    @State private var pillHideTask: Task<Void, Never>?
    @State private var gearHideTask: Task<Void, Never>?
    @State private var isShowingPluginsPanel = false

    /// Заметка для плашки What’s new; nil — плашки нет.
    @State private var whatsNewNote = WhatsNew.pendingNote()
    /// После ✕ плашка пару секунд подсказывает, где найти заметки.
    @State private var isShowingWhatsNewHint = false

    private var isEditingWorkspaceName: Bool { renamingSlot != nil }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Group {
                    if isEditingWorkspaceName {
                        TextField("Space name", text: $workspaceNameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .frame(width: 100)
                            .focused($isWorkspaceNameFieldFocused)
                            .onSubmit { commitWorkspaceRename() }
                            .onExitCommand { cancelWorkspaceRename() }
                            .onChange(of: isWorkspaceNameFieldFocused) { _, focused in
                                if !focused { commitWorkspaceRename() }
                            }
                            .onChange(of: workspaceNameDraft) { _, newValue in
                                if newValue.count > BoardViewModel.maxWorkspaceNameLength {
                                    workspaceNameDraft = String(newValue.prefix(BoardViewModel.maxWorkspaceNameLength))
                                }
                            }
                    } else {
                        Text(viewModel.activeWorkspaceName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isEditingWorkspaceName {
                        dismissToolbarTooltip()
                        startWorkspaceRename()
                    }
                }
                .onHover { inside in
                    guard !isEditingWorkspaceName else { return }
                    setToolbarHover(inside, "Rename")
                }
                .overlay(alignment: .top) { toolbarTooltip("Rename") }

                // Иконки-действия пристёгнуты к тому же pill'у, что и
                // название — не отдельные капсулы под ним, чтобы новая
                // функция была ещё одной иконкой в этом же ряду, а не
                // ещё одной строкой вниз.
                if !isEditingWorkspaceName {
                    let items = ToolbarItem.allCases.filter { isEditingToolbar || !toolbarSettings.isHidden($0) }
                    if !items.isEmpty {
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 1, height: 14)
                    }
                    ForEach(Array(items.enumerated()), id: \.element) { index, item in
                        if isEditingToolbar {
                            editableIcon(item, phase: index)
                        } else {
                            toolbarIcon(item)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            // Название/иконки — фиксированно белые в обеих темах. Материал
            // даёт настоящее размытие (плоский чёрный тон на цветных обоях
            // в Desktop Overlay грязно гасит фон), тон сверху — только чтобы
            // белый текст оставался читаемым; в Light Mode он легче.
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.black.opacity(colorScheme == .dark ? 0.1 : 0.18)))
            )
            .onHover { inside in setPillHover(inside) }
            // За капсулой (background), а не поверх: кружок выезжает из-под неё.
            .background(alignment: .trailing) { gearButton }

            if isAskingSpaceAI {
                askAIPanel
            } else if isShowingPluginsPanel {
                pluginsPanel
            } else if let whatsNewNote, !isOnboardingActive {
                whatsNewBanner(whatsNewNote)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearTextSelection)) { _ in
            // Клик по свободному холсту закрывает панель Ask AI, но
            // только если в поле ещё ничего не напечатано — не хотим
            // терять черновик вопроса случайным кликом мимо.
            guard isAskingSpaceAI, spaceAIQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            withAnimation(spaceAISpring) { isAskingSpaceAI = false }
        }
        .onChange(of: isFocusModeActive) { _, active in
            if active {
                isAskingSpaceAI = false
                isShowingPluginsPanel = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearTextSelection)) { _ in
            // Клик по свободному холсту — конец правки капсулы и закрытие панели Plugins.
            if isEditingToolbar { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isEditingToolbar = false } }
            if isShowingPluginsPanel { withAnimation(spaceAISpring) { isShowingPluginsPanel = false } }
        }
        .onChange(of: viewModel.activeSlot) { _, _ in
            commitWorkspaceRename()
        }
        .alert("AI Error", isPresented: Binding(
            get: { spaceAIErrorMessage != nil },
            set: { if !$0 { spaceAIErrorMessage = nil } }
        )) {
            Button("OK") { spaceAIErrorMessage = nil }
        } message: {
            Text(spaceAIErrorMessage ?? "")
        }
    }

    private var spaceAISpring: Animation { .spring(response: 0.4, dampingFraction: 0.76) }

    // MARK: - Иконки капсулы

    /// Обычная иконка-действие.
    @ViewBuilder
    private func toolbarIcon(_ item: ToolbarItem) -> some View {
        switch item {
        case .askAI:
            // Развёрнутая на 45° звёздочка читается как крестик —
            // понятная подсказка "нажми ещё раз, чтобы закрыть".
            toolbarButton("Ask AI", icon: item.symbol, isActive: isAskingSpaceAI, rotation: isAskingSpaceAI ? 45 : 0) {
                // Если в этот момент печатали в какой-то карточке,
                // её текстовое поле удерживает first responder —
                // панель Ask AI должна явно получить его, а не
                // соревноваться за фокус в тот же момент.
                NSApp.keyWindow?.makeFirstResponder(nil)
                withAnimation(spaceAISpring) {
                    isShowingPluginsPanel = false
                    isAskingSpaceAI.toggle()
                }
            }
        case .tidyCards:
            toolbarButton("Tidy Cards", icon: item.symbol) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    viewModel.tidyCards(canvasSize: canvasSize, topInset: topInset)
                }
            }
            .disabled(viewModel.cards.isEmpty)
        case .clearSpace:
            toolbarButton("Clear Space", icon: item.symbol) {
                NotificationCenter.default.post(name: .requestClearSpace, object: nil)
            }
            .disabled(viewModel.cards.isEmpty)
        case .plugins:
            toolbarButton("Plugins", icon: item.symbol, isActive: isShowingPluginsPanel) {
                NSApp.keyWindow?.makeFirstResponder(nil)
                withAnimation(spaceAISpring) {
                    isAskingSpaceAI = false
                    isShowingPluginsPanel.toggle()
                }
            }
        }
    }

    /// Иконка в режиме правки: дрожит; «−» — скрыть, у скрытой (приглушена) «+» — вернуть.
    private func editableIcon(_ item: ToolbarItem, phase: Int) -> some View {
        let isHidden = toolbarSettings.isHidden(item)
        return Image(systemName: item.symbol)
            .font(.system(size: 15))
            .foregroundStyle(Color.white.opacity(isHidden ? 0.35 : 0.9))
            .modifier(WobbleEffect(phase: phase))
            .overlay(alignment: .topLeading) {
                Image(systemName: isHidden ? "plus" : "minus")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 12, height: 12)
                    .background(Circle().fill(isHidden ? Color.green : Color.red))
                    .offset(x: -8, y: -7)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    toolbarSettings.setHidden(item, !isHidden)
                    if item == .plugins, !isHidden { isShowingPluginsPanel = false }
                    if item == .askAI, !isHidden { isAskingSpaceAI = false }
                }
            }
    }

    // MARK: - Шестерёнка

    private var isGearShown: Bool { isHoveringPill || isHoveringGear || isEditingToolbar }

    /// Отдельный кружок справа от капсулы: выплывает из неё по наведению. Левый
    /// отступ внутри области нажатия закрывает зазор между капсулой и кружком —
    /// иначе при переходе мыши он успевал бы исчезнуть.
    private var gearButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { isEditingToolbar.toggle() }
        } label: {
            Image(systemName: isEditingToolbar ? "checkmark" : "gearshape.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isEditingToolbar ? 0.95 : 0.6))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(isEditingToolbar ? Color.accentColor.opacity(0.6) : Color.black.opacity(colorScheme == .dark ? 0.1 : 0.18)))
                )
                .padding(.leading, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isEditingToolbar ? "Done" : "Customize toolbar")
        .onHover { inside in setGearHover(inside) }
        // Полупрозрачный в покое; едет из-под капсулы вправо, без масштабирования.
        .opacity(isGearShown ? (isEditingToolbar ? 1 : 0.7) : 0)
        .allowsHitTesting(isGearShown)
        .offset(x: isGearShown ? 26 + 12 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isGearShown)
    }

    /// У капсулы и у кружка — каждому свой таймер скрытия: общий отменял бы чужой,
    /// и флаг наведения на капсулу «застревал» бы включённым.
    /// Кружок появляется не сразу (450 мс наведения), а пропадает чуть быстрее.
    private func setPillHover(_ inside: Bool) {
        pillHideTask?.cancel()
        pillHideTask = Task {
            try? await Task.sleep(for: .milliseconds(inside ? 450 : 220))
            guard !Task.isCancelled else { return }
            isHoveringPill = inside
        }
    }

    private func setGearHover(_ inside: Bool) {
        gearHideTask?.cancel()
        if inside {
            isHoveringGear = true
        } else {
            gearHideTask = Task {
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                isHoveringGear = false
            }
        }
    }

    // MARK: - Панель Plugins

    private var pluginsPanel: some View {
        let plugins = PluginsModel.shared
        return VStack(alignment: .leading, spacing: 10) {
            Text("Plugins")
                .font(.system(size: 13, weight: .semibold))
            if plugins.installed.isEmpty {
                Text("No plugins yet. Plugins add fonts, themes and card templates.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(plugins.installed) { plugin in
                    HStack {
                        Text(plugin.name).font(.system(size: 12))
                        Spacer()
                        Text(plugin.isEnabled ? "On" : "Off")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                withAnimation(spaceAISpring) { isShowingPluginsPanel = false }
                SettingsNavigation.shared.open(.plugins)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Plugins\u{2026}")
                    Spacer()
                }
                .font(.system(size: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 260, alignment: .leading)
        .background(
            CardSurfaceBackground(
                cornerRadius: 16,
                usesGlassEffect: false,
                tintOpacity: 0.15,
                materialStyle: .thickMaterial,
                lightMaterialStyle: .ultraThinMaterial,
                lightTintOpacity: 0.2
            )
        )
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.5, anchor: .top).combined(with: .opacity).animation(spaceAISpring),
                removal: .scale(scale: 0.5, anchor: .top).combined(with: .opacity).animation(.easeIn(duration: 0.15))
            )
        )
    }

    /// Как у Arc: «обновились» + What’s new (карточка с заметками по центру
    /// Space) или ✕ (подсказка, где заметки лежат, и плашка уходит).
    private func whatsNewBanner(_ note: ReleaseNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isShowingWhatsNewHint {
                Text("Read it anytime in Settings \u{2192} About \u{2192} Release Notes.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("Thoughts updated to \(note.version)")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "sparkle")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Button {
                        dismissWhatsNew()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
                Button {
                    openWhatsNew(note)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gift")
                        Text("What\u{2019}s new")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 240)
        .background(
            CardSurfaceBackground(
                cornerRadius: 16,
                usesGlassEffect: false,
                tintOpacity: 0.15,
                materialStyle: .thickMaterial,
                lightMaterialStyle: .ultraThinMaterial,
                lightTintOpacity: 0.2
            )
        )
        .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
    }

    private func openWhatsNew(_ note: ReleaseNote) {
        WhatsNew.markSeen()
        let size = CGSize(width: 360, height: 440)
        let origin = CGPoint(
            x: max(0, (canvasSize.width - size.width) / 2),
            y: max(0, (canvasSize.height - size.height) / 2)
        )
        withAnimation(spaceAISpring) {
            // Свечение по краям, как у карточки ответа AI, — до первого касания.
            let card = viewModel.addCard(at: origin, size: size, text: WhatsNew.markdown(for: note))
            viewModel.aiHighlightedCardIDs.insert(card.id)
            whatsNewNote = nil
        }
    }

    private func dismissWhatsNew() {
        WhatsNew.markSeen()
        withAnimation(.easeInOut(duration: 0.2)) { isShowingWhatsNewHint = true }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeIn(duration: 0.25)) { whatsNewNote = nil }
        }
    }

    /// Раскрывается/закрывается через insertion/removal с масштабом от
    /// верхнего края и пружиной на входе. В левом нижнем углу поля — выбор провайдера
    /// (AIProviderMenu), как во всех панелях Ask AI; если выбранный
    /// недоступен, вместо поля — AIUnavailableNotice.
    private var askAIPanel: some View {
        Group {
            if viewModel.aiSettings.hasKey(for: viewModel.aiSettings.selectedProvider) {
                spaceAIPrompt
            } else {
                AIUnavailableNotice(showsProviderMenu: true)
                    .frame(height: 130)
            }
        }
        .padding(6)
        .frame(width: 300)
        .background(
            CardSurfaceBackground(
                cornerRadius: 16,
                usesGlassEffect: false,
                tintOpacity: 0.15,
                materialStyle: .thickMaterial,
                lightMaterialStyle: .ultraThinMaterial,
                lightTintOpacity: 0.2
            )
        )
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.5, anchor: .top).combined(with: .opacity)
                    .animation(spaceAISpring),
                removal: .scale(scale: 0.5, anchor: .top).combined(with: .opacity)
                    .animation(.easeIn(duration: 0.15))
            )
        )
    }

    private var spaceAIPrompt: some View {
        AIPromptField(
            text: $spaceAIQuestion,
            placeholder: "Ask about your project\u{2026}",
            shouldFocus: isAskingSpaceAI,
            isBusy: isSpaceAIBusy,
            height: 130,
            onSend: askSpaceAI
        )
        .frame(maxWidth: .infinity)
        .onExitCommand {
            withAnimation(spaceAISpring) { isAskingSpaceAI = false }
            spaceAIQuestion = ""
        }
    }

    private func spaceAIContextText() -> String {
        viewModel.cards
            .filter { $0.privacyMode == .none && !$0.text.isEmpty }
            .map { "<note>\n\($0.text)\n</note>" }
            .joined(separator: "\n")
    }

    private func askSpaceAI() {
        let question = spaceAIQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSpaceAIBusy else { return }
        let context = spaceAIContextText()
        // Ответ — в тот Space, где спросили, даже если пока ждали, переключились.
        let slot = viewModel.activeSlot
        isSpaceAIBusy = true
        Task {
            do {
                let result = try await AITextServiceFactory.ask(
                    question,
                    context: context,
                    contextLabel: "Notes",
                    questionLabel: "Question",
                    systemPrompt: AISpaceAction.askSystemPrompt
                )
                insertAIResultCard(result, slot: slot)
                spaceAIQuestion = ""
                withAnimation(spaceAISpring) { isAskingSpaceAI = false }
                isSpaceAIBusy = false
            } catch {
                spaceAIErrorMessage = error.localizedDescription
                isSpaceAIBusy = false
            }
        }
    }

    /// Не выставляет newlyCreatedCardID — та карточка сразу получает фокус
    /// текстового ввода (.focusNewCard), что фактически "активирует" её и
    /// сразу же снимало бы постоянную AI-подсветку (см. aiHighlightedCardIDs
    /// и CardView) прежде, чем пользователь вообще успеет её заметить.
    private func insertAIResultCard(_ text: String, slot: Int) {
        let size = CGSize(width: 280, height: 220)
        let origin = CGPoint(
            x: max(0, (canvasSize.width - size.width) / 2),
            y: max(0, (canvasSize.height - size.height) / 2)
        )
        let card = viewModel.addCard(at: origin, size: size, slot: slot, text: text, isAIGenerated: true)
        viewModel.aiHighlightedCardIDs.insert(card.id)
    }

    /// Не просто `hoveredToolbarLabel = inside ? label : nil` — если курсор
    /// уходит с одной иконки сразу на соседнюю, exit-событие первой может
    /// прийти ПОСЛЕ enter-события второй, и голое присваивание стёрло бы
    /// уже выставленный новый label. Очищаем только если он всё ещё
    /// принадлежит этой же иконке.
    private func setToolbarHover(_ inside: Bool, _ label: String) {
        if inside {
            hoveredToolbarLabel = label
        } else if hoveredToolbarLabel == label {
            hoveredToolbarLabel = nil
        }

        tooltipTask?.cancel()
        if inside {
            tooltipTask = Task {
                try? await Task.sleep(for: .seconds(0.45))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.1)) {
                    tooltipVisibleLabel = label
                }
            }
        } else if tooltipVisibleLabel == label {
            withAnimation(.easeOut(duration: 0.08)) {
                tooltipVisibleLabel = nil
            }
        }
    }

    /// Иконка-действие на плашке Space: подсветка при наведении и подсказка
    /// с задержкой; label — и текст подсказки, и ключ hover-состояния.
    private func toolbarButton(
        _ label: String,
        icon: String,
        isActive: Bool = false,
        rotation: Double = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            dismissToolbarTooltip()
            action()
        } label: {
            Image(systemName: icon)
                .rotationEffect(.degrees(rotation))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white.opacity(isActive || hoveredToolbarLabel == label ? 1 : 0.85))
        .font(.system(size: 15))
        .onHover { setToolbarHover($0, label) }
        .overlay(alignment: .top) { toolbarTooltip(label) }
    }

    /// Отдельно от setToolbarHover — щёлкая по кнопке, курсор физически
    /// остаётся на месте (onHover не получает "мышь ушла"), так что без
    /// явной отмены подсказка осталась бы висеть поверх уже открытой панели.
    private func dismissToolbarTooltip() {
        tooltipTask?.cancel()
        tooltipVisibleLabel = nil
    }

    @ViewBuilder
    private func toolbarTooltip(_ label: String) -> some View {
        if tooltipVisibleLabel == label {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                // Обычный Color.black.opacity(...) на и без того тёмном
                // фоне канвы визуально неотличим от полностью непрозрачного
                // — настоящий материал реально размывает/пропускает то,
                // что под ним, а не просто гасит альфой поверх тёмного.
                // Сам материал светлый в Light Mode — белый текст поверх
                // него без тона нечитаем, поэтому дотемняем чёрным тоном
                // (в Dark Mode тон не нужен — материал и так тёмный).
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(0.9))
                        .overlay(Capsule().fill(Color.black.opacity(colorScheme == .dark ? 0 : 0.18)))
                )
                .fixedSize()
                .allowsHitTesting(false)
                .offset(y: 24)
                .transition(.opacity)
        }
    }

    private func startWorkspaceRename() {
        workspaceNameDraft = viewModel.activeWorkspaceName
        renamingSlot = viewModel.activeSlot
        DispatchQueue.main.async {
            isWorkspaceNameFieldFocused = true
        }
    }

    private func commitWorkspaceRename() {
        guard let slot = renamingSlot else { return }
        viewModel.renameWorkspace(slot: slot, to: workspaceNameDraft)
        renamingSlot = nil
    }

    private func cancelWorkspaceRename() {
        renamingSlot = nil
    }
}

/// Лёгкая «тряска» иконок в режиме правки капсулы — как в iOS при перестановке
/// приложений; фаза у каждой иконки своя, чтобы они не качались в унисон.
private struct WobbleEffect: ViewModifier {
    let phase: Int
    @State private var isOn = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isOn ? 2.2 : -2.2))
            .animation(
                .easeInOut(duration: 0.12 + Double(phase % 3) * 0.015).repeatForever(autoreverses: true),
                value: isOn
            )
            .onAppear { isOn = true }
    }
}
