import SwiftUI

// Анимации онбординга — код, а не видео: чёткие в любом разрешении, в обеих темах,
// без файлов. Каждая сцена — функция времени `t` внутри цикла длиной `period`
// (TimelineView), так что её не сбивают другие анимации. При «Reduce Motion» —
// один статичный кадр (`still`).

/// Часы сцены: `t` от 0 до `period`, по кругу.
struct SceneClock<Content: View>: View {
    var period: Double
    /// Кадр для Reduce Motion — момент, где видно всё главное.
    var still: Double
    @ViewBuilder var content: (Double) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? still : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
            content(t)
        }
    }
}

/// 0 → 1 между `from` и `to`, с мягким началом и концом.
func sceneProgress(_ t: Double, from: Double, to: Double) -> Double {
    guard to > from else { return t >= to ? 1 : 0 }
    let x = min(max((t - from) / (to - from), 0), 1)
    return x * x * (3 - 2 * x)
}

// MARK: - Детали

/// Карточка в миниатюре: тёмная поверхность, моноширинный текст, точка тега.
struct FakeCard: View {
    var text: String
    var tag: Color?
    var fontSize: CGFloat = 10

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.16).opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            Text(text)
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            if let tag {
                Circle().fill(tag).frame(width: 6, height: 6)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .padding(7)
            }
        }
    }
}

/// Стрелка курсора; `pressed` — чуть меньше, как при нажатии.
struct FakeCursor: View {
    var pressed = false

    var body: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
            .scaleEffect(pressed ? 0.88 : 1, anchor: .topLeading)
    }
}

/// Тёмная канва с лёгким градиентом — фон сцен.
struct FakeCanvas: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.17, green: 0.17, blue: 0.22), Color(red: 0.11, green: 0.11, blue: 0.14)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

/// Обои рабочего стола: тёплый градиент, иконки папок справа.
struct FakeDesktop: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.27, blue: 0.55), Color(red: 0.86, green: 0.47, blue: 0.38)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    Image(systemName: "folder.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(red: 0.45, green: 0.72, blue: 0.98))
                }
            }
            .padding(10)
        }
    }
}

// MARK: - Сцены

/// Экран 1: карточки появляются одна за другой и сами «печатаются», у одной
/// загорается тег. Цикл 9 с.
struct HookScene: View {
    private struct Item { let text: String; let x: CGFloat; let y: CGFloat; let w: CGFloat; let h: CGFloat; let at: Double }
    private let items = [
        Item(text: "big idea \u{2728}", x: 0.06, y: 0.12, w: 0.30, h: 0.30, at: 0.4),
        Item(text: "buy milk\n- [ ] eggs", x: 0.42, y: 0.08, w: 0.26, h: 0.36, at: 1.6),
        Item(text: "call mom", x: 0.72, y: 0.20, w: 0.22, h: 0.24, at: 2.8),
        Item(text: "trip: Tbilisi\nlate May?", x: 0.18, y: 0.55, w: 0.32, h: 0.32, at: 4.0),
        Item(text: "## Plan\nship 1.4.1", x: 0.58, y: 0.56, w: 0.30, h: 0.32, at: 5.2)
    ]

    var body: some View {
        SceneClock(period: 9, still: 8) { t in
            GeometryReader { proxy in
                let size = proxy.size
                ZStack(alignment: .topLeading) {
                    FakeCanvas()
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        let appear = sceneProgress(t, from: item.at, to: item.at + 0.35)
                        let typed = Int(max(0, (t - item.at - 0.3) * 22))
                        let fadeOut = 1 - sceneProgress(t, from: 8.4, to: 9)
                        FakeCard(text: String(item.text.prefix(typed)),
                                 tag: index == 1 && t > 6.6 ? .orange : (index == 4 && t > 7.2 ? .purple : nil))
                            .frame(width: item.w * size.width, height: item.h * size.height)
                            .scaleEffect(0.85 + 0.15 * appear)
                            .opacity(appear * fadeOut)
                            .offset(x: item.x * size.width, y: item.y * size.height)
                    }
                }
            }
        }
    }
}

/// Экран 2, вариант «окно»: обычное окно с кнопками и карточками внутри.
struct WindowHomeScene: View {
    var body: some View {
        SceneClock(period: 4, still: 0) { t in
            GeometryReader { proxy in
                let size = proxy.size
                let bob = sin(t / 4 * 2 * .pi) * 2
                ZStack {
                    FakeDesktop()
                    VStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.red.opacity(0.85)).frame(width: 6, height: 6)
                            Circle().fill(Color.yellow.opacity(0.85)).frame(width: 6, height: 6)
                            Circle().fill(Color.green.opacity(0.85)).frame(width: 6, height: 6)
                            Spacer()
                        }
                        .padding(6)
                        HStack(spacing: 6) {
                            FakeCard(text: "idea", tag: nil, fontSize: 7)
                            FakeCard(text: "todo", tag: .orange, fontSize: 7)
                        }
                        .padding(8)
                        .offset(y: bob)
                    }
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(white: 0.12)))
                    .frame(width: size.width * 0.66, height: size.height * 0.62)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                }
            }
        }
    }
}

/// Экран 2, вариант «рабочий стол»: карточки лежат прямо на обоях, рядом с папками.
struct DesktopHomeScene: View {
    var body: some View {
        SceneClock(period: 4, still: 0) { t in
            GeometryReader { proxy in
                let size = proxy.size
                ZStack(alignment: .topLeading) {
                    FakeDesktop()
                    ForEach(0..<3, id: \.self) { index in
                        let bob = sin((t / 4 + Double(index) * 0.3) * 2 * .pi) * 2
                        FakeCard(text: ["idea", "todo", "plan"][index], tag: index == 1 ? .orange : nil, fontSize: 7)
                            .frame(width: size.width * 0.24, height: size.height * 0.3)
                            .offset(x: size.width * (0.08 + 0.26 * CGFloat(index)),
                                    y: size.height * (index == 1 ? 0.48 : 0.16) + bob)
                    }
                }
            }
        }
    }
}

/// Экран 3: курсор тянет по канве — появляется рамка новой карточки. Цикл 2.6 с.
struct CreateCardScene: View {
    var body: some View {
        SceneClock(period: 2.6, still: 1.6) { t in
            GeometryReader { proxy in
                let size = proxy.size
                let start = CGPoint(x: size.width * 0.22, y: size.height * 0.22)
                let grow = sceneProgress(t, from: 0.4, to: 1.5)
                let end = CGPoint(x: start.x + size.width * 0.52 * grow, y: start.y + size.height * 0.5 * grow)
                let pressed = t > 0.3 && t < 1.7
                let fade = 1 - sceneProgress(t, from: 2.1, to: 2.6)
                ZStack(alignment: .topLeading) {
                    FakeCanvas()
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .frame(width: end.x - start.x, height: end.y - start.y)
                        .offset(x: start.x, y: start.y)
                        .opacity(grow > 0.02 ? fade : 0)
                    FakeCursor(pressed: pressed)
                        .offset(x: end.x - 2, y: end.y - 2)
                        .opacity(fade)
                }
            }
        }
    }
}

/// Финал: вспышка-галочка и шорткаты чипами.
struct FinishScene: View {
    var body: some View {
        SceneClock(period: 3, still: 2) { t in
            let pop = sceneProgress(t, from: 0, to: 0.45)
            let glow = 0.5 + 0.5 * sin(t / 3 * 2 * .pi)
            ZStack {
                FakeCanvas()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.accentColor)
                    .shadow(color: Color.accentColor.opacity(0.35 + 0.35 * glow), radius: 16)
                    .scaleEffect(0.7 + 0.3 * pop)
            }
        }
    }
}
