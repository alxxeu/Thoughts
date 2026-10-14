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
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 1, height: 14)

                    // Развёрнутая на 45° звёздочка читается как крестик —
                    // понятная подсказка "нажми ещё раз, чтобы закрыть".
                    toolbarButton("Ask AI", icon: "sparkle", isActive: isAskingSpaceAI, rotation: isAskingSpaceAI ? 45 : 0) {
                        // Если в этот момент печатали в какой-то карточке,
                        // её текстовое поле удерживает first responder —
                        // панель Ask AI должна явно получить его, а не
                        // соревноваться за фокус в тот же момент.
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        withAnimation(spaceAISpring) { isAskingSpaceAI.toggle() }
                    }

                    toolbarButton("Tidy Cards", icon: "square.grid.2x2.fill") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            viewModel.tidyCards(canvasSize: canvasSize, topInset: topInset)
                        }
                    }
                    .disabled(viewModel.cards.isEmpty)

                    toolbarButton("Clear Space", icon: "trash.fill") {
                        NotificationCenter.default.post(name: .requestClearSpace, object: nil)
                    }
                    .disabled(viewModel.cards.isEmpty)
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

            if isAskingSpaceAI {
                askAIPanel
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
            if active { isAskingSpaceAI = false }
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
            .map(\.text)
            .joined(separator: "\n---\n")
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
