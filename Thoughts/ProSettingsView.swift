import SwiftUI

/// Справочный список функций будущей подписки Pro — только для показа,
/// подписки как рантайм-механизма (StoreKit/entitlement) ещё не
/// существует. Часть этих функций уже реализована в коде (Tidy Cards,
/// BYOK для ChatGPT/Claude), но нефункциональна в этой сборке — их UI
/// в других местах приложения (тулбар, AI-настройки) просто ведёт сюда.
/// Оформление сознательно яркое/привлекающее внимание — это единственный
/// "рекламный" экран в приложении.

// MARK: - Общая фиолетово-синяя палитра

/// Цветочек в хэдере и иконки функций ниже сознательно используют одну и
/// ту же пару цветов вместо разрозненных (было: синий/оранжевый/бирюзовый/
/// розовый) — светлый лавандовый тон подобран по базовому цвету иконки
/// приложения (AppIcon.icon/icon.json, display-p3 0.679/0.707/0.969),
/// снизу — насыщенный индиго-фиолетовый.
private let proGradientStart = (r: 0.40, g: 0.33, b: 0.80) // насыщенный индиго-фиолетовый
private let proGradientEnd = (r: 0.72, g: 0.74, b: 0.98) // светлый лавандовый (тон иконки приложения)
private let proGradientColors: [Color] = [
    Color(.displayP3, red: proGradientStart.r, green: proGradientStart.g, blue: proGradientStart.b),
    Color(.displayP3, red: proGradientEnd.r, green: proGradientEnd.g, blue: proGradientEnd.b)
]
private let proGradient = LinearGradient(colors: proGradientColors, startPoint: .bottom, endPoint: .top)

/// Не градиент ВНУТРИ каждой иконки, а один сплошной цвет НА иконку,
/// подобранный так, чтобы сами иконки, идя по списку сверху вниз, сами
/// складывались в градиент — тот же приём, что в Telegram Premium
/// (каждый пункт списка — свой сплошной цвет, но соседние цвета близки).
private func proSequenceColor(fraction: Double) -> Color {
    Color(
        .displayP3,
        red: proGradientStart.r + (proGradientEnd.r - proGradientStart.r) * fraction,
        green: proGradientStart.g + (proGradientEnd.g - proGradientStart.g) * fraction,
        blue: proGradientStart.b + (proGradientEnd.b - proGradientStart.b) * fraction
    )
}

// MARK: - Кастомная иконка-цветочек

/// В SF Symbols нет подходящего "цветочка" — рисуем сами. Каждый лепесток
/// — асимметричная кривая (стороны не зеркальны), из-за чего фигура целиком
/// читается как крутящаяся вертушка/цветок (в духе иконки Arc), а не как
/// симметричная ромашка. Не private — переиспользуется в SettingsView.swift
/// для иконки таба (см. proTabIcon ниже).
struct FlowerShape: Shape {
    var petalCount: Int = 4

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let length = radius * 0.98
        let width = length * 0.6

        var petal = Path()
        petal.move(to: .zero)
        petal.addCurve(
            to: CGPoint(x: 0, y: -length),
            control1: CGPoint(x: -width * 0.75, y: -length * 0.08),
            control2: CGPoint(x: -width * 0.5, y: -length * 0.75)
        )
        petal.addCurve(
            to: .zero,
            control1: CGPoint(x: width * 0.22, y: -length * 0.92),
            control2: CGPoint(x: width * 0.12, y: -length * 0.28)
        )
        petal.closeSubpath()

        var combined = Path()
        for i in 0..<petalCount {
            let angle = (2 * .pi / CGFloat(petalCount)) * CGFloat(i) - .pi / 2
            let transform = CGAffineTransform(rotationAngle: angle)
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
            combined.addPath(petal, transform: transform)
        }
        return combined
    }
}

/// Иконка-цветочек для таба Settings → Pro (вместо "crown.fill"). Тут
/// нужен monochrome template-image, а не цветной градиент — как и у
/// остальных системных SF Symbol-иконок табов, чтобы macOS сам красил её в
/// синий при выборе таба и в серый в остальное время (сплошная заливка
/// чёрным + isTemplate — так система понимает, что можно перекрашивать).
let proTabIcon: Image = {
    // Просто уменьшить общий размер картинки не сработало — таб-бар сам
    // нормализует итоговый размер иконки под соседние SF Symbol'ы
    // независимо от заявленного point-size изображения (проверено: смена
    // 44×44 → 22×22 не дала видимой разницы). У SF Symbol'ов вроде
    // "gearshape" сам штрих не касается краёв — вокруг всегда есть
    // оптический отступ. Наша фигура рисуется краешек-в-краешек, поэтому
    // выглядит крупнее при той же итоговой рамке — добавляем такой же
    // отступ явно: цветочек рисуется в маленьком квадрате, а холст для
    // рендера — заметно больше него.
    let flowerBoxSize: CGFloat = 22
    let canvasSize: CGFloat = 40
    let content = FlowerShape()
        .fill(Color.black)
        .frame(width: flowerBoxSize, height: flowerBoxSize)
        .frame(width: canvasSize, height: canvasSize)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 6
    guard let nsImage = renderer.nsImage else { return Image(systemName: "seal.fill") }
    nsImage.isTemplate = true
    return Image(nsImage: nsImage)
}()

// MARK: - Список функций

private struct ProFeatureInfo: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
}

private let proFeatures: [ProFeatureInfo] = [
    ProFeatureInfo(
        title: "Tidy Cards",
        subtitle: "Automatically arrange every card into a clean grid.",
        symbol: "square.grid.2x2.fill"
    ),
    ProFeatureInfo(
        title: "Bring Your Own API Key",
        subtitle: "Use ChatGPT or Claude with your own key instead of Apple Intelligence.",
        symbol: "key.fill"
    ),
    ProFeatureInfo(
        title: "Unlimited Spaces",
        subtitle: "Go beyond the default number of Spaces, with the freedom to reassign which Space each keyboard shortcut opens.",
        symbol: "square.stack.3d.up.fill"
    ),
    ProFeatureInfo(
        title: "Space Collaboration",
        subtitle: "Share a Space and work on it together in real time.",
        symbol: "person.2.fill"
    )
]

private struct ProFeatureRow: View {
    let feature: ProFeatureInfo
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                Text(feature.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Ручной аналог фона Form-секции — сам таб больше не на Form (см.
/// ProSettingsTab: нужен реальный ScrollView, чтобы отслеживать позицию
/// скролла и схлопывать хэдер), поэтому системную "grouped"-коробку взять
/// неоткуда, рисуем её эквивалент сами.
private struct GroupedBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
    }
}

// MARK: - Бесплатный бета-доступ

/// Кнопка-ссылка — прямое открытие через Link, тот же приём, что уже
/// используют GitHub/Telegram в табе About. Никакого упоминания доната/
/// оплаты в этом файле — тема доната озвучивается пользователем лично, в
/// переписке, не в приложении (условие легальности по гайдлайну 3.1.1
/// App Store).
private struct ProContactButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title).fontWeight(.semibold)
            }
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().fill(tint.gradient))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Таб

/// Полный хэдер (цветочек + заголовок) — часть прокручиваемого содержимого,
/// не прибит поверх списка функций: при скролле уходит вверх вместе с
/// остальным контентом и сменяется компактной закреплённой строкой
/// (compactHeader) — тот же приём, что даёт "сворачивающийся" large title
/// в системных приложениях (Settings, Mail).
struct ProSettingsTab: View {
    @State private var isHeaderCollapsed = false

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 16) {
                    fullHeader

                    GroupedBox {
                        ForEach(Array(proFeatures.enumerated()), id: \.element.id) { index, feature in
                            let fraction = proFeatures.count > 1 ? Double(index) / Double(proFeatures.count - 1) : 0
                            ProFeatureRow(feature: feature, color: proSequenceColor(fraction: fraction))
                            if index != proFeatures.count - 1 {
                                Divider().padding(.leading, 12 + 28 + 12)
                            }
                        }
                    }

                    Text("These features are already built and will unlock once Pro launches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)

                    GroupedBox {
                        VStack(spacing: 8) {
                            Text("Free Beta Access")
                                .font(.system(size: 13, weight: .semibold))
                            Text("We\u{2019}re inviting a limited group to try Pro for free via TestFlight while we\u{2019}re in testing. Want in? Email us or message us on Telegram below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            HStack(spacing: 8) {
                                ProContactButton(
                                    title: "Email",
                                    symbol: "envelope.fill",
                                    tint: .blue,
                                    url: URL(string: "mailto:alxxeu.dev@proton.me?subject=Thoughts%20Pro%20Beta%20Access")!
                                )
                                ProContactButton(
                                    title: "Telegram",
                                    symbol: "paperplane.fill",
                                    tint: Color(red: 0.16, green: 0.68, blue: 0.94),
                                    url: URL(string: "https://t.me/alxeu")!
                                )
                            }
                        }
                        .padding(12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 16)
            }
            .proScrollCollapse { offset in
                let shouldCollapse = offset > 24
                if shouldCollapse != isHeaderCollapsed {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHeaderCollapsed = shouldCollapse
                    }
                }
            }

            compactHeader
        }
    }

    private var fullHeader: some View {
        VStack(spacing: 18) {
            FlowerShape()
                .fill(proGradient)
                .frame(width: 52, height: 52)
            HStack(spacing: 6) {
                Text("Thoughts Pro")
                    .font(.system(size: 16, weight: .bold))
                Text("Coming later")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .foregroundStyle(.white)
                    .background(
                        Capsule().fill(
                            LinearGradient(colors: proGradientColors, startPoint: .leading, endPoint: .trailing)
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Видна только когда полный хэдер прокрутился за пределы видимой
    /// области (isHeaderCollapsed) — не участвует в layout остальных
    /// элементов (это overlay поверх ScrollView, не часть его содержимого).
    private var compactHeader: some View {
        HStack(spacing: 4) {
            Text("Thoughts Pro")
                .font(.system(size: 12, weight: .semibold))
            Text("(Coming later)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .opacity(isHeaderCollapsed ? 1 : 0)
        .allowsHitTesting(false)
    }
}

/// `onScrollGeometryChange` (macOS 15+) — официальный API именно для этой
/// задачи, надёжнее самодельного трюка с GeometryReader+PreferenceKey
/// внутри прокручиваемого содержимого (тот вариант молчал: minY навсегда
/// застревал на 0, ни разу не обновившись при реальном скролле — вероятно,
/// особенность того, как ScrollView на этой версии macOS применяет
/// смещение). На macOS < 15 хэдер просто не схлопывается — не критично,
/// целевая аудитория (TestFlight, последние macOS) не пострадает.
private extension View {
    @ViewBuilder
    func proScrollCollapse(onOffsetChange: @escaping (CGFloat) -> Void) -> some View {
        if #available(macOS 15.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                onOffsetChange(newValue)
            }
        } else {
            self
        }
    }
}
