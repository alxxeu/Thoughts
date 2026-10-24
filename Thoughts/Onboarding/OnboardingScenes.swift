import SwiftUI

// Анимации онбординга — код, а не видео: чёткие в любом разрешении, в обеих темах,
// без файлов. Каждая сцена — функция времени `t` внутри цикла длиной `period`
// (TimelineView), так что её не сбивают другие анимации. «Reduce Motion» их не
// останавливает: это обучающие демонстрации в рамке (курсор, набор текста), без
// параллакса и крупных движений, и без анимации они ничего не объясняют.

/// Часы сцены: `t` от 0 до `period`, по кругу.
struct SceneClock<Content: View>: View {
    var period: Double
    /// Кадр, где видно всё главное (для превью и тестов).
    var still: Double
    @ViewBuilder var content: (Double) -> Content

    var body: some View {
        TimelineView(.animation) { context in
            content(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period))
        }
    }
}

/// 0 → 1 между `from` и `to`, с мягким началом и концом.
func sceneProgress(_ t: Double, from: Double, to: Double) -> Double {
    guard to > from else { return t >= to ? 1 : 0 }
    let x = min(max((t - from) / (to - from), 0), 1)
    return x * x * (3 - 2 * x)
}

/// Путь курсора по ключевым точкам (время, точка в долях сцены); между ними — плавно.
struct CursorPath {
    let keys: [(t: Double, x: CGFloat, y: CGFloat)]

    func point(at t: Double, in size: CGSize) -> CGPoint {
        guard let first = keys.first else { return .zero }
        var previous = first
        for key in keys {
            if t <= key.t {
                let p = CGFloat(sceneProgress(t, from: previous.t, to: key.t))
                return CGPoint(x: (previous.x + (key.x - previous.x) * p) * size.width,
                               y: (previous.y + (key.y - previous.y) * p) * size.height)
            }
            previous = key
        }
        return CGPoint(x: previous.x * size.width, y: previous.y * size.height)
    }
}

// MARK: - Детали

/// Стеклянная подложка Desktop Overlay: лежит поверх обоев и папок (они видны
/// сквозь неё размытыми), на ней — карточки.
struct FakeGlassPanel: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}

/// Строки карточки с живым Markdown, как в приложении: `# ` — заголовок,
/// `- [ ] ` / `- [x] ` — чек-лист, `**…**` — жирный. `typed` — сколько символов
/// уже «напечатано» (по всем строкам подряд).
struct MarkdownLines: View {
    var lines: [String]
    var typed: Int = .max
    var fontSize: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
    }

    private var visibleLines: [String] {
        var budget = typed
        var result: [String] = []
        for line in lines {
            guard budget > 0 else { break }
            result.append(String(line.prefix(budget)))
            budget -= line.count
        }
        return result
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if line.hasPrefix("# ") {
            inline(String(line.dropFirst(2)))
                .font(.system(size: fontSize * 1.45, weight: .bold, design: .monospaced))
        } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [ ] ") {
            let done = line.hasPrefix("- [x] ")
            HStack(spacing: 4) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.system(size: fontSize))
                    .foregroundStyle(done ? Color.accentColor : .white.opacity(0.6))
                inline(String(line.dropFirst(6)))
                    .strikethrough(done)
                    .opacity(done ? 0.5 : 1)
            }
            .font(.system(size: fontSize, design: .monospaced))
        } else if line.hasPrefix("- [") || line == "-" || line == "- " {
            // Маркер ещё печатается — как в приложении, скрыт до пробела.
            Text(" ").font(.system(size: fontSize, design: .monospaced))
        } else {
            inline(line).font(.system(size: fontSize, design: .monospaced))
        }
    }

    private func inline(_ text: String) -> Text {
        Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
    }
}

/// Карточка в миниатюре: та же тёмная поверхность, Markdown внутри, точка тега.
struct FakeCard: View {
    var lines: [String]
    var typed: Int = .max
    var tag: Color?
    /// Пустой кружок тега (наведение) — как у настоящей карточки.
    var showsTagSlot = false
    /// Крестик удаления и его кольцо (0…1).
    var deleteProgress: Double? = nil
    var fontSize: CGFloat = 10

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.16).opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            MarkdownLines(lines: lines, typed: typed, fontSize: fontSize)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 9)
                .padding(.top, deleteProgress == nil ? 8 : 18)
            if let tag {
                Circle().fill(tag).frame(width: 7, height: 7)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .padding(7)
            } else if showsTagSlot {
                Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1).frame(width: 7, height: 7)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .padding(7)
            }
            if let deleteProgress {
                ZStack {
                    Circle().fill(Color.white.opacity(deleteProgress > 0 ? 0.22 : 0.12))
                    Circle().trim(from: 0, to: deleteProgress)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "xmark")
                        .font(.system(size: 6, weight: .black))
                        .foregroundStyle(deleteProgress > 0 ? Color.red : Color.white.opacity(0.55))
                }
                .frame(width: 13, height: 13)
                .padding(4)
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
            .scaleEffect(pressed ? 0.85 : 1, anchor: .topLeading)
    }
}

/// Тёмная канва с лёгким градиентом — фон сцен.
struct FakeCanvas: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.17, green: 0.17, blue: 0.22), Color(red: 0.11, green: 0.11, blue: 0.14)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
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

// MARK: - Экран 1: крючок

/// Курсор сам рисует три карточки, в них печатается живой Markdown (заголовок,
/// жирный, чек-лист), курсор отмечает пункт и ставит тег. Цикл 13 с.
struct HookScene: View {
    private struct Draft {
        let rect: CGRect          // в долях сцены
        let drawFrom: Double      // курсор тянет рамку
        let typeFrom: Double      // печать
        let lines: [String]
    }

    private let drafts = [
        Draft(rect: CGRect(x: 0.05, y: 0.08, width: 0.40, height: 0.40), drawFrom: 0.3, typeFrom: 1.4,
              lines: ["# Big idea", "ship **1.4.2**", "on Friday"]),
        Draft(rect: CGRect(x: 0.52, y: 0.06, width: 0.43, height: 0.50), drawFrom: 3.0, typeFrom: 4.1,
              lines: ["# Groceries", "- [ ] milk", "- [ ] eggs", "- [ ] coffee"]),
        Draft(rect: CGRect(x: 0.14, y: 0.58, width: 0.40, height: 0.34), drawFrom: 7.4, typeFrom: 8.5,
              lines: ["call **mom**", "about the trip"])
    ]
    private static let typingSpeed = 24.0
    private static let checkAt = 6.9
    private static let tagAt = 10.6

    private var cursor: CursorPath {
        CursorPath(keys: [
            (0.0, 0.40, 0.70),
            (0.3, 0.05, 0.08), (1.2, 0.45, 0.48),          // рамка 1
            (2.0, 0.60, 0.70),
            (3.0, 0.52, 0.06), (3.9, 0.95, 0.56),          // рамка 2
            (6.2, 0.80, 0.60), (6.8, 0.565, 0.235),        // к чекбоксу «milk»
            (7.4, 0.14, 0.58), (8.3, 0.54, 0.92),          // рамка 3
            (9.8, 0.70, 0.80), (10.5, 0.515, 0.62),        // к точке тега
            (13.0, 0.40, 0.70)
        ])
    }

    var body: some View {
        SceneClock(period: 13, still: 11.5) { t in
            GeometryReader { proxy in
                let size = proxy.size
                let fade = 1 - sceneProgress(t, from: 12.3, to: 13)
                let pressed = (t > 0.3 && t < 1.2) || (t > 3.0 && t < 3.9) || (t > 7.4 && t < 8.3)
                    || abs(t - Self.checkAt) < 0.12 || abs(t - Self.tagAt) < 0.12
                ZStack(alignment: .topLeading) {
                    FakeCanvas()
                    ForEach(drafts.indices, id: \.self) { index in
                        card(index, t: t, size: size).opacity(fade)
                    }
                    let point = cursor.point(at: t, in: size)
                    FakeCursor(pressed: pressed)
                        .offset(x: point.x - 2, y: point.y - 2)
                        .opacity(fade)
                }
            }
        }
    }

    private func card(_ index: Int, t: Double, size: CGSize) -> AnyView {
        let draft = drafts[index]
        let drawEnd = draft.drawFrom + 0.9
        guard t >= draft.drawFrom else { return AnyView(EmptyView()) }
        let grow = CGFloat(sceneProgress(t, from: draft.drawFrom, to: drawEnd))
        let frame = CGRect(x: draft.rect.minX * size.width, y: draft.rect.minY * size.height,
                           width: max(4, draft.rect.width * size.width * grow),
                           height: max(4, draft.rect.height * size.height * grow))
        if t < drawEnd {
            // Рамка, которую тянет курсор, — как при создании карточки.
            return AnyView(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            )
        }
        let typed = Int(max(0, (t - draft.typeFrom) * Self.typingSpeed))
        var lines = draft.lines
        if index == 1, t >= Self.checkAt { lines[1] = "- [x] milk" }
        let tag: Color? = index == 2 && t >= Self.tagAt ? .orange : (index == 1 ? .green : nil)
        return AnyView(
            FakeCard(lines: lines, typed: typed, tag: tag, showsTagSlot: index == 2 && t > 9.8)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        )
    }
}

// MARK: - Экран 2: где жить

/// Вариант «окно»: обычное окно с кнопками и карточками внутри. Пропорции
/// карточек — от ширины сцены, а не от высоты: высокая плитка не растягивает их.
struct WindowHomeScene: View {
    var body: some View {
        SceneClock(period: 4, still: 0) { t in
            GeometryReader { proxy in
                let size = proxy.size
                let bob = sin(t / 4 * 2 * .pi) * 2
                let windowWidth = size.width * 0.72
                let cardWidth = (windowWidth - 8 * 3) / 2
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
                        HStack(alignment: .top, spacing: 8) {
                            FakeCard(lines: ["# idea", "ship it"], fontSize: 7)
                                .frame(width: cardWidth, height: cardWidth * 0.78)
                            FakeCard(lines: ["- [ ] todo", "- [x] done"], tag: .orange, fontSize: 7)
                                .frame(width: cardWidth, height: cardWidth * 0.62)
                        }
                        .padding(8)
                        .offset(y: bob)
                        Spacer(minLength: 0)
                    }
                    .frame(width: windowWidth, height: windowWidth * 0.66)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(white: 0.12)))
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                }
            }
        }
    }
}

/// Вариант «рабочий стол»: по ⌥1 на обоях появляется стеклянная подложка с
/// карточками (папки видны сквозь неё), потом всё уходит и цикл повторяется.
struct DesktopHomeScene: View {
    private let cards: [(lines: [String], tag: Color?, x: CGFloat, y: CGFloat, aspect: CGFloat)] = [
        (["# idea", "ship it"], nil, 0.07, 0.22, 0.78),
        (["- [ ] todo", "- [x] done"], .orange, 0.42, 0.42, 0.62),
        (["**plan**", "May"], nil, 0.12, 0.62, 0.55)
    ]
    private static let period = 6.0

    var body: some View {
        SceneClock(period: Self.period, still: 3) { t in
            GeometryReader { proxy in
                let size = proxy.size
                let cardWidth = size.width * 0.34
                let glass = sceneProgress(t, from: 0.7, to: 1.3) - sceneProgress(t, from: 5.2, to: 5.7)
                let pressed = (t > 0.25 && t < 1.0) || t > 5.0 && t < 5.6
                ZStack(alignment: .topLeading) {
                    FakeDesktop()
                    FakeGlassPanel()
                        .frame(width: size.width * 0.94, height: size.height * 0.94)
                        .offset(x: size.width * 0.03, y: size.height * 0.03)
                        .opacity(glass)
                        .scaleEffect(0.94 + 0.06 * glass)
                    ForEach(cards.indices, id: \.self) { index in
                        let card = cards[index]
                        let appear = sceneProgress(t, from: 1.1 + Double(index) * 0.25, to: 1.6 + Double(index) * 0.25)
                            - sceneProgress(t, from: 5.2, to: 5.7)
                        let bob = sin((t / Self.period + Double(index) * 0.3) * 2 * .pi) * 2
                        FakeCard(lines: card.lines, tag: card.tag, fontSize: 7)
                            .frame(width: cardWidth, height: cardWidth * card.aspect)
                            .scaleEffect(0.9 + 0.1 * appear)
                            .opacity(appear)
                            .offset(x: size.width * card.x, y: size.height * card.y + bob)
                    }
                    HStack(spacing: 4) {
                        KeyCap(label: "\u{2325}", pressed: pressed)
                        KeyCap(label: t < 3 ? "1" : "D", pressed: pressed)
                    }
                    .scaleEffect(0.62)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 2)
                }
            }
        }
    }
}

// MARK: - Экран 3: демонстрации заданий

/// Курсор тянет по канве — появляется рамка новой карточки. Цикл 2.6 с.
struct CreateCardScene: View {
    var body: some View {
        SceneClock(period: 2.6, still: 1.6) { t in
            GeometryReader { proxy in
                let size = proxy.size
                let start = CGPoint(x: size.width * 0.18, y: size.height * 0.2)
                let grow = sceneProgress(t, from: 0.4, to: 1.5)
                let end = CGPoint(x: start.x + size.width * 0.58 * grow, y: start.y + size.height * 0.55 * grow)
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
                    FakeCursor(pressed: t > 0.3 && t < 1.7)
                        .offset(x: end.x - 2, y: end.y - 2)
                        .opacity(fade)
                }
            }
        }
    }
}

/// В карточке печатается текст с Markdown. Цикл 4 с.
struct TypeTextScene: View {
    var body: some View {
        SceneClock(period: 4, still: 3) { t in
            ZStack {
                FakeCanvas()
                FakeCard(lines: ["# Hello", "my **first** thought"], typed: Int(max(0, (t - 0.3) * 14)))
                    .padding(.horizontal, 30)
                    .padding(.vertical, 18)
                    .opacity(1 - sceneProgress(t, from: 3.6, to: 4))
            }
        }
    }
}

/// Курсор кликает по кружку тега — появляются цвета — выбирает оранжевый,
/// кружок окрашивается. Цикл 3.8 с.
struct TagCursorScene: View {
    var body: some View {
        SceneClock(period: 3.8, still: 2.6) { t in
            GeometryReader { proxy in
                let size = proxy.size
                let card = CGRect(x: size.width * 0.12, y: size.height * 0.16, width: size.width * 0.76, height: size.height * 0.62)
                let dot = CGPoint(x: card.maxX - 10, y: card.minY + 10)
                let colors: [Color] = [.red, .orange, .yellow, .green]
                let orange = CGPoint(x: dot.x - 30 + 20, y: dot.y + 24)
                let path = CursorPath(keys: [
                    (0.0, (card.midX) / size.width, (card.maxY + 8) / size.height),
                    (0.8, dot.x / size.width, dot.y / size.height),
                    (1.5, dot.x / size.width, dot.y / size.height),
                    (2.0, orange.x / size.width, orange.y / size.height),
                    (3.8, orange.x / size.width, orange.y / size.height)
                ])
                let picked = t >= 2.15
                let menuOpen = t >= 0.95 && t < 2.3
                ZStack(alignment: .topLeading) {
                    FakeCanvas()
                    FakeCard(lines: ["# Trip", "late May?"], tag: picked ? .orange : nil, showsTagSlot: true)
                        .frame(width: card.width, height: card.height)
                        .offset(x: card.minX, y: card.minY)
                    if menuOpen {
                        HStack(spacing: 6) {
                            ForEach(colors.indices, id: \.self) { i in
                                Circle().fill(colors[i]).frame(width: 10, height: 10)
                            }
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(white: 0.22)))
                        .offset(x: dot.x - 40, y: dot.y + 12)
                        .transition(.opacity)
                    }
                    let point = path.point(at: t, in: size)
                    FakeCursor(pressed: abs(t - 0.9) < 0.1 || abs(t - 2.1) < 0.1)
                        .offset(x: point.x - 2, y: point.y - 2)
                }
            }
        }
    }
}

/// Курсор зажимает крестик — вокруг заполняется красное кольцо — карточка
/// исчезает. Цикл 3.4 с.
struct DeleteCursorScene: View {
    var body: some View {
        SceneClock(period: 3.4, still: 1.4) { t in
            GeometryReader { proxy in
                let size = proxy.size
                let card = CGRect(x: size.width * 0.12, y: size.height * 0.16, width: size.width * 0.76, height: size.height * 0.62)
                let cross = CGPoint(x: card.minX + 10, y: card.minY + 10)
                let path = CursorPath(keys: [
                    (0.0, card.midX / size.width, (card.maxY + 8) / size.height),
                    (0.8, cross.x / size.width, cross.y / size.height),
                    (3.4, cross.x / size.width, cross.y / size.height)
                ])
                let ring = sceneProgress(t, from: 0.9, to: 1.5)
                let gone = sceneProgress(t, from: 1.55, to: 1.9)
                let back = sceneProgress(t, from: 2.9, to: 3.3)
                let visible = gone < 1 ? 1 - gone : back
                ZStack(alignment: .topLeading) {
                    FakeCanvas()
                    FakeCard(lines: ["# Draft", "not needed"], deleteProgress: t < 1.9 ? ring : 0)
                        .frame(width: card.width, height: card.height)
                        .scaleEffect(0.85 + 0.15 * visible)
                        .opacity(visible)
                        .offset(x: card.minX, y: card.minY)
                    let point = path.point(at: t, in: size)
                    FakeCursor(pressed: t > 0.85 && t < 1.6)
                        .offset(x: point.x - 2, y: point.y - 2)
                }
            }
        }
    }
}

// MARK: - Финал: горячие клавиши

/// Клавиши и что они делают: ⌥Tab — обзор Spaces (выбор идёт по плиткам), ⌥1–9 —
/// прыжок в Space, ⌥D — карточки уходят, остаются обои, и ⌥1–9 возвращает их
/// (последнее — только для рабочего стола).
struct HotkeysScene: View {
    var showsDesktop: Bool
    /// Длительности сегментов: ⌥Tab, ⌥1–9, ⌥D + возврат.
    private static let segments: [Double] = [2.4, 2.6, 5.2]

    private var durations: [Double] { showsDesktop ? Self.segments : Array(Self.segments.prefix(2)) }

    var body: some View {
        SceneClock(period: durations.reduce(0, +), still: 1) { t in
            let (index, local) = segment(at: t)
            ZStack {
                if index < 2 {
                    SpaceGridBackdrop()
                    GeometryReader { proxy in
                        SpaceGrid(selection: selection(index, local))
                            .frame(width: proxy.size.width * 0.78, height: proxy.size.height * 0.62)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.4)
                    }
                } else {
                    DesktopHideScene(hidden: hidden(local))
                }
                VStack {
                    Spacer()
                    keys(index, local)
                        .padding(.bottom, 22)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func segment(at t: Double) -> (Int, Double) {
        var start = 0.0
        for (index, length) in durations.enumerated() {
            if t < start + length || index == durations.count - 1 { return (index, t - start) }
            start += length
        }
        return (0, t)
    }

    /// Карточки уходят по ⌥D и возвращаются по ⌥1–9.
    private func hidden(_ local: Double) -> Double {
        sceneProgress(local, from: 0.8, to: 1.2) - sceneProgress(local, from: 3.6, to: 4.0)
    }

    /// Выбранная плитка: ⌥Tab — идёт по плиткам, ⌥1–9 — прыгает.
    private func selection(_ index: Int, _ local: Double) -> Int {
        if index == 0 { return local < 0.8 ? 0 : (local < 1.2 ? 1 : (local < 1.6 ? 2 : 3)) }
        return local < 0.9 ? 3 : (local < 1.8 ? 7 : 5)
    }

    private func keys(_ index: Int, _ local: Double) -> some View {
        let label: String
        let pressed: Bool
        switch index {
        case 0:
            label = "Tab"
            pressed = local > 0.15 && local < 2.0
        case 1:
            label = local < 0.9 ? "4" : (local < 1.8 ? "8" : "6")
            pressed = local > 0.15 && local < 2.2
        default:
            // ⌥D, пауза, затем ⌥2 — возврат карточек.
            label = local < 2.6 ? "D" : "2"
            pressed = (local > 0.3 && local < 1.6) || (local > 3.4 && local < 4.6)
        }
        return HStack(spacing: 8) {
            KeyCap(label: "\u{2325}", pressed: pressed)
            Text("+").foregroundStyle(.white.opacity(0.4))
            KeyCap(label: label, pressed: pressed)
        }
    }
}

/// Цветной фон обзора ⌥Tab — как обои, но темнее.
private struct SpaceGridBackdrop: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.15, blue: 0.32), Color(red: 0.46, green: 0.24, blue: 0.22)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

/// Клавиша: приподнятая, при нажатии темнеет и «вдавливается».
struct KeyCap: View {
    var label: String
    var pressed: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(pressed ? 1 : 0.8))
            .frame(minWidth: 40, minHeight: 34)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(pressed ? 0.28 : 0.14)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
            .offset(y: pressed ? 1.5 : 0)
    }
}

/// Девять миниатюр Spaces, как в обзоре ⌥Tab; выбранная — с рамкой.
private struct SpaceGrid: View {
    var selection: Int
    private let cards: [[(CGFloat, CGFloat, CGFloat, CGFloat)]] = [
        [(0.1, 0.15, 0.4, 0.35), (0.5, 0.5, 0.4, 0.35)], [(0.15, 0.2, 0.7, 0.3)], [(0.1, 0.1, 0.35, 0.5), (0.55, 0.3, 0.35, 0.5)]
    ]

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 8
            let w = (proxy.size.width - gap * 2) / 3, h = (proxy.size.height - gap * 2) / 3
            ForEach(0..<9, id: \.self) { slot in
                let selected = slot == selection
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay {
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(cards[slot % 3].enumerated()), id: \.offset) { _, c in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color.white.opacity(0.25))
                                    .frame(width: w * c.2, height: h * c.3)
                                    .offset(x: w * c.0, y: h * c.1)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.12), lineWidth: selected ? 2.5 : 0.5))
                    .frame(width: w, height: h)
                    .offset(x: CGFloat(slot % 3) * (w + gap), y: CGFloat(slot / 3) * (h + gap))
            }
        }
    }
}

/// Рабочий стол с карточками; `hidden` 0…1 — карточки уходят (⌥D), остаются обои.
private struct DesktopHideScene: View {
    var hidden: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                FakeDesktop()
                FakeGlassPanel()
                    .frame(width: size.width * 0.94, height: size.height * 0.94)
                    .offset(x: size.width * 0.03, y: size.height * 0.03)
                    .opacity(1 - hidden)
                Group {
                    FakeCard(lines: ["# idea", "ship it"], fontSize: 7)
                        .frame(width: size.width * 0.3, height: size.width * 0.23)
                        .offset(x: size.width * 0.08, y: size.height * 0.2)
                    FakeCard(lines: ["- [ ] todo", "- [x] done"], tag: .orange, fontSize: 7)
                        .frame(width: size.width * 0.3, height: size.width * 0.19)
                        .offset(x: size.width * 0.4, y: size.height * 0.4)
                }
                .opacity(1 - hidden)
                .scaleEffect(1 - 0.06 * hidden)
            }
        }
    }
}
