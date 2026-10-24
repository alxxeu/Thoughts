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
                // Темы из плагинов: выбор применяет шрифт, цвет и паттерн разом.
                if !ThemeOption.plugins.isEmpty {
                    LabeledContent("Theme Preset") {
                        Menu("Apply\u{2026}") {
                            ForEach(ThemeOption.plugins) { theme in
                                Button(theme.title) { settings.apply(theme) }
                            }
                        }
                        .fixedSize()
                    }
                }

                Picker("Font", selection: Binding(
                    get: { settings.cardFontID },
                    set: { settings.cardFontID = $0 }
                )) {
                    ForEach(CardFontOption.builtIn) { option in
                        Text(option.title).tag(option.id)
                    }
                    if !CardFontOption.plugins.isEmpty {
                        Divider()
                        ForEach(CardFontOption.plugins) { option in
                            Text(option.title).tag(option.id)
                        }
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
                        ForEach(TextColorOption.builtIn + TextColorOption.plugins) { option in
                            colorSwatch(option)
                        }
                        ForEach(settings.recentTextColorIDs.map(TextColorOption.resolve)) { option in
                            colorSwatch(option)
                        }
                        ColorPicker("Custom Color", selection: customColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .help("Custom Color")
                    }
                }
            }

            Section {
                Picker("Pattern", selection: Binding(
                    get: { settings.canvasPatternID },
                    set: { settings.canvasPatternID = $0 }
                )) {
                    ForEach(CanvasPattern.builtIn) { pattern in
                        Text(pattern.title).tag(pattern.id)
                    }
                    if !CanvasPattern.plugins.isEmpty {
                        Divider()
                        ForEach(CanvasPattern.plugins) { pattern in
                            Text(pattern.title).tag(pattern.id)
                        }
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

                LabeledContent("Background") {
                    HStack(spacing: 8) {
                        // Свои обои — первыми: выбрана — открывает выбор другой картинки,
                        // не выбрана, но есть — выбирает её, нет — открывает выбор.
                        Button {
                            if settings.backgroundID != BackgroundChoice.imageID, BackgroundImageStore.shared.hasImage {
                                settings.backgroundID = BackgroundChoice.imageID
                            } else {
                                settings.chooseBackgroundImage(message: "Choose an image for the background")
                            }
                        } label: {
                            imageSwatch
                        }
                        .buttonStyle(.plain)
                        .help("Your image")
                        .contextMenu {
                            Button("Choose Image\u{2026}") {
                                settings.chooseBackgroundImage(message: "Choose an image for the background")
                            }
                            // Панель откроется в папке, где лежат нынешние обои, — без права записи экрана.
                            Button("Use Current Wallpaper\u{2026}") {
                                settings.chooseBackgroundImage(startingIn: BackgroundImagePicker.currentWallpaperFolder,
                                                               message: "Choose your current wallpaper")
                            }
                        }
                        // Material — размытие того, что под окном.
                        Button { settings.backgroundID = BackgroundChoice.materialID } label: {
                            materialSwatch
                        }
                        .buttonStyle(.plain)
                        .help("Material \u{2014} blurs what is behind the window")
                        ForEach(FullScreenBackgroundOption.builtIn + settings.recentBackgroundIDs.map(FullScreenBackgroundOption.resolve)) { option in
                            swatch(option.color, title: option.title, isSelected: settings.backgroundID == option.id) {
                                settings.backgroundID = option.id
                            }
                        }
                        ColorPicker("Custom Color", selection: backgroundColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .help("Custom Color")
                    }
                }
            } header: {
                Text("Background")
            } footer: {
                Text("Material blurs what is behind the window. Material, a color or your own image works the same in a window, in full screen and on the desktop. Right-click the image button to choose another picture or use your current wallpaper.")
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
            // Фон по настройке; для Material — то же размытие вживую (файл обоев из
            // песочницы не прочитать, а desktopImageURL после смены обоев отдаёт старый путь).
            if case .material = settings.background {
                PreviewBackdrop()
            } else {
                AppBackgroundView(settings: settings)
            }
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
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: - Text color

    private func colorSwatch(_ option: TextColorOption) -> some View {
        swatch(option.color, title: option.title, isSelected: settings.textColorID == option.id) {
            settings.textColorID = option.id
        }
    }

    private func swatch(_ color: NSColor, title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: color))
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
        .help(title)
    }

    private var materialSwatch: some View {
        MaterialSwatchArt()
            .frame(width: 16, height: 16)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
            .padding(3)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2)
                .opacity(settings.backgroundID == BackgroundChoice.materialID ? 1 : 0))
    }

    /// Свои обои: миниатюра картинки, пока её нет — значок фото.
    private var imageSwatch: some View {
        Group {
            if let image = BackgroundImageStore.shared.image {
                let _ = settings.backgroundImageRevision
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.12))
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
        .padding(3)
        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2)
            .opacity(settings.backgroundID == BackgroundChoice.imageID ? 1 : 0))
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                if case .color(let option) = settings.background { return Color(nsColor: option.color) }
                return Color(nsColor: FullScreenBackgroundOption.resolve(FullScreenBackgroundOption.defaultID).color)
            },
            set: { settings.pickCustomBackground(NSColor($0)) }
        )
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.cardTypography.color) },
            set: { settings.pickCustomTextColor(NSColor($0)) }
        )
    }
}

/// Размытие того, что лежит под окном Settings (обои рабочего стола), — как
/// фон главного окна, но без его подталкиваний окна при смене Spaces.
private struct PreviewBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Картинка значка Material: горизонтальная радуга, правая половина закрыта настоящим
/// материалом — он размывает полосы под собой, как размывает обои под окном.
struct MaterialSwatchArt: View {
    private static let stripes: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                ForEach(Self.stripes.indices, id: \.self) { Self.stripes[$0] }
            }
            Rectangle().fill(.ultraThinMaterial).frame(width: 8)
        }
    }
}
