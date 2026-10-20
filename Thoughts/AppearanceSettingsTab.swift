import SwiftUI
import AppKit

/// Таб Appearance в Settings: тема, шрифт и цвет текста карточек, паттерн
/// фона канвы. Сами варианты описаны данными в Customization.swift.
struct AppearanceSettingsTab: View {
    var settings: AppearanceSettings

    /// Список установленных семейств — один раз на открытие таба, а не на
    /// каждый body (NSFontManager отдаёт несколько сотен строк).
    @State private var installedFamilies: [String] = []

    var body: some View {
        Form {
            Section {
                preview
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Picker("Theme", selection: Binding(
                    get: { settings.colorScheme },
                    set: { settings.colorScheme = $0 }
                )) {
                    ForEach(AppColorScheme.allCases) { scheme in
                        Text(scheme.title).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Auto follows your Mac's system appearance.")
            }

            Section("Cards") {
                Picker("Font", selection: Binding(
                    get: { settings.cardFontID },
                    set: { settings.cardFontID = $0 }
                )) {
                    ForEach(CardFontOption.builtIn) { option in
                        Text(option.title).tag(option.id)
                    }
                    if !installedFamilies.isEmpty {
                        Divider()
                        ForEach(installedFamilies, id: \.self) { family in
                            Text(family).tag(CardFontOption.family(family).id)
                        }
                    }
                }

                Picker("Text Size", selection: Binding(
                    get: { settings.textSize },
                    set: { settings.textSize = $0 }
                )) {
                    ForEach(CardTextSize.allCases) { size in
                        Text(size.title)
                            .accessibilityLabel(size.accessibilityName)
                            .help(size.accessibilityName)
                            .tag(size)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Text Color") {
                    HStack(spacing: 8) {
                        ForEach(TextColorOption.builtIn) { option in
                            colorSwatch(option)
                        }
                        ColorPicker("Custom Color", selection: customColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .help("Custom Color")
                    }
                }
            }

            Section("Background") {
                Picker("Pattern", selection: Binding(
                    get: { settings.canvasPatternID },
                    set: { settings.canvasPatternID = $0 }
                )) {
                    ForEach(CanvasPattern.builtIn) { pattern in
                        Text(pattern.title).tag(pattern.id)
                    }
                }

                LabeledContent("Intensity") {
                    Slider(
                        value: Binding(
                            get: { settings.patternOpacity },
                            set: { settings.patternOpacity = $0 }
                        ),
                        in: AppearanceSettings.patternOpacityRange
                    )
                    .frame(maxWidth: 200)
                }
                .disabled(settings.canvasPattern.kind == .none)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if installedFamilies.isEmpty {
                installedFamilies = CardFontOption.installedFamilies
            }
        }
    }

    // MARK: - Preview

    /// Мини-канва с одной карточкой — те же CardSurfaceBackground и
    /// CanvasPatternView, что и на настоящей канве, чтобы превью не
    /// расходилось с результатом.
    private var preview: some View {
        let typography = settings.cardTypography
        let font = Font(typography.font as CTFont)
        let color = Color(nsColor: typography.color)

        return ZStack {
            Color(nsColor: .underPageBackgroundColor)
            CanvasPatternView(pattern: settings.canvasPattern, opacity: settings.patternOpacity)

            VStack(alignment: .leading, spacing: 6) {
                Text("Scattered ideas")
                    .font(font.bold())
                Text("No folders, no lists \u{2014} just space to think.")
                    .font(font)
            }
            .foregroundStyle(color)
            .padding(16)
            .frame(width: 240, alignment: .topLeading)
            .background(CardSurfaceBackground())
        }
        .frame(height: 170)
        .clipped()
    }

    // MARK: - Text color

    private func colorSwatch(_ option: TextColorOption) -> some View {
        let isSelected = settings.textColorID == option.id
        return Button {
            settings.textColorID = option.id
        } label: {
            Circle()
                .fill(Color(nsColor: option.color))
                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                .frame(width: 16, height: 16)
                .padding(3)
                .overlay(
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .opacity(isSelected ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .help(option.title)
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.cardTypography.color) },
            set: { settings.textColorID = TextColorOption.custom(NSColor($0)).id }
        )
    }
}
