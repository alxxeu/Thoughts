import SwiftUI

/// Ask AI под карточкой в Focus Mode: кнопка "Ask AI…", разворачивающаяся в
/// панель во всю ширину карточки. Живёт, только пока виден футер фокуса, —
/// при выходе из фокуса вид пропадает вместе со всем своим состоянием.
struct CardAskAIPanel: View {
    @Bindable var card: Card
    var viewModel: BoardViewModel
    /// Клик обратно в текст карточки закрывает панель: пока она открыта,
    /// курсор живёт в её собственном поле, так что возврат фокуса в текст —
    /// однозначный сигнал "я снова пишу".
    @Binding var isTextFocused: Bool
    /// Идёт запрос — карточка показывает свой индикатор поверх текста.
    @Binding var isGenerating: Bool

    // Панель Ask AI под карточкой — только в Focus Mode. Ответ не правит
    // текст карточки сам: он показывается под заданным вопросом, а что с
    // ним делать, решают кнопки Insert Below / Replace / Ask Again.
    @State private var isShowingCardAI = false
    @State private var cardAIQuestion = ""
    @State private var cardAIAnswer: String?
    @State private var cardAIPlaceholder = AICardPrompt.randomSuggestion()
    @State private var aiErrorMessage: String?

    private var cardAIAnimation: Animation { .easeInOut(duration: 0.22) }

    var body: some View {
        Group {
            if isShowingCardAI {
                cardAskAIPanel
            } else {
                askAIButton
            }
        }
        .onChange(of: isTextFocused) { _, focused in
            if focused, isShowingCardAI {
                collapseCardAI()
            }
        }
        .alert("AI Error", isPresented: Binding(
            get: { aiErrorMessage != nil },
            set: { if !$0 { aiErrorMessage = nil } }
        )) {
            Button("OK") { aiErrorMessage = nil }
        } message: {
            Text(aiErrorMessage ?? "")
        }
    }

    private var askAIButton: some View {
        Button {
            // Пока пользователь печатал в самой карточке, её текстовое
            // поле удерживает first responder — панель Ask AI должна
            // явно получить его, а не соревноваться за фокус в тот же
            // момент. isTextFocused = false тем же путём, что и обычная
            // потеря фокуса, уводит первый respond'ер с CardTextView.
            isTextFocused = false
            cardAIPlaceholder = AICardPrompt.randomSuggestion()
            withAnimation(cardAIAnimation) { isShowingCardAI = true }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkle")
                    .font(.system(size: 10))
                Text("Ask AI\u{2026}")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }

    /// Тот же визуальный язык, что у SpaceToolbar.askAIPanel, но скоуп —
    /// ровно эта карточка, и по ширине панель совпадает с ней. Фиксированных
    /// инструментов нет — свободная формулировка, подсказанная примером в
    /// пустом поле (как и в "Ask AI" из контекстного меню текста).
    private var cardAskAIPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let answer = cardAIAnswer {
                Text(cardAIQuestion)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)

                ScrollView {
                    Text(answer)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundStyle(Color.white.opacity(0.88))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                }
                .frame(height: 150)
                // Гасится сам текст, а не подкладывается плашка сверху —
                // тогда край гарантированно сходится с фоном панели, каким
                // бы он ни был. Тот же приём уже используется у текста
                // карточки (CardTextView в CardView.body).
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.82),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                cardAIActionBar(for: answer)
            } else if !viewModel.aiSettings.hasKey(for: viewModel.aiSettings.selectedProvider) {
                AIUnavailableNotice(showsProviderMenu: true)
                    .frame(height: 96)
                    .padding(12)
            } else {
                AIPromptField(
                    text: $cardAIQuestion,
                    placeholder: cardAIPlaceholder,
                    shouldFocus: isShowingCardAI,
                    isBusy: isGenerating,
                    height: 96,
                    sendIconSize: 22,
                    onSend: askCardAI
                )
                .padding(12)
            }
        }
        .frame(width: BoardViewModel.focusCardSize.width)
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
        .transition(.opacity)
    }

    /// Собственного фона у панели действий нет — она лежит прямо на фоне
    /// всей панели Ask AI, поэтому цвет совпадает с ним по определению, и
    /// нижние скругления панели ничем не перекрываются.
    private func cardAIActionBar(for answer: String) -> some View {
        HStack(spacing: 10) {
            cardAIChip(title: "Insert Below", systemImage: "text.insert") {
                card.text += (card.text.isEmpty ? "" : "\n\n") + answer
                viewModel.scheduleDebouncedSave()
                collapseCardAI()
            }
            cardAIChip(title: "Replace", systemImage: "arrow.triangle.2.circlepath") {
                card.text = answer
                viewModel.scheduleDebouncedSave()
                collapseCardAI()
            }
            cardAIChip(title: "Ask Again", systemImage: "arrow.counterclockwise") {
                cardAIAnswer = nil
                cardAIQuestion = ""
                cardAIPlaceholder = AICardPrompt.randomSuggestion()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .padding(.horizontal, 18)
    }

    private func cardAIChip(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Результат НЕ попадает в карточку сам — показывается под вопросом,
    /// пользователь сам решает, дописать его, заменить им текст или
    /// спросить заново.
    private func askCardAI() {
        let question = cardAIQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isGenerating else { return }
        let context = card.text
        isGenerating = true
        Task {
            do {
                let result = try await AITextServiceFactory.ask(
                    question,
                    context: context,
                    contextLabel: "Note",
                    systemPrompt: AICardPrompt.systemPrompt
                )
                cardAIAnswer = result
                isGenerating = false
            } catch {
                aiErrorMessage = error.localizedDescription
                isGenerating = false
            }
        }
    }

    private func collapseCardAI() {
        withAnimation(cardAIAnimation) { isShowingCardAI = false }
        cardAIQuestion = ""
        cardAIAnswer = nil
    }
}
