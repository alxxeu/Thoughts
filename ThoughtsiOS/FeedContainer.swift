import SwiftUI
import UIKit

/// Общее состояние ленты и нижней панели — они живут в разных UIHostingController.
@Observable
final class FeedModel {
    var slot = 1
    var draft = ""
    var spacesCollapsed = false
    /// Поле ввода в фокусе (клавиатура поднята или поднимается).
    var typing = false

    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Как у Signal: лента — на весь экран с постоянной рамкой (клавиатура в её safe area не входит),
/// нижняя панель прижата к `keyboardLayoutGuide`, нижний отступ ленты задаёт высота контейнера панели
/// (`additionalSafeAreaInsets`). Панель едет в анимации клавиатуры, а не в своей.
struct FeedContainer<Feed: View, Bar: View>: UIViewControllerRepresentable {
    let feed: Feed
    let bar: Bar

    func makeUIViewController(context: Context) -> FeedContainerViewController {
        FeedContainerViewController(feed: AnyView(feed), bar: AnyView(bar))
    }

    func updateUIViewController(_ vc: FeedContainerViewController, context: Context) {
        vc.feedHost.rootView = AnyView(feed)
        vc.barHost.rootView = AnyView(bar)
    }
}

final class FeedContainerViewController: UIViewController {
    let feedHost: UIHostingController<AnyView>
    let barHost: UIHostingController<AnyView>
    private let fadeHost = UIHostingController(rootView: BottomFade())

    init(feed: AnyView, bar: AnyView) {
        feedHost = UIHostingController(rootView: feed)
        barHost = UIHostingController(rootView: bar)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .clear

        feedHost.safeAreaRegions = .container // клавиатура в safe area ленты не входит
        feedHost.view.backgroundColor = .clear
        add(feedHost)
        feedHost.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            feedHost.view.topAnchor.constraint(equalTo: view.topAnchor),
            feedHost.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            feedHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            feedHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Затухание под панелью: на 40 pt выше неё и до низа экрана.
        fadeHost.view.backgroundColor = .clear
        fadeHost.view.isUserInteractionEnabled = false
        add(fadeHost)
        fadeHost.view.translatesAutoresizingMaskIntoConstraints = false

        // Панель = поле + полоса Spaces, высота постоянная. Верх полосы Spaces — всегда над безопасной зоной,
        // а поле стоит на клавиатуре (guide.usesBottomSafeArea = false, WWDC23): клавиатура просто закрывает полосу,
        // панель при этом не меняет высоту и не прыгает — как у Signal.
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        barHost.sizingOptions = [.intrinsicContentSize]
        barHost.safeAreaRegions = []
        barHost.view.backgroundColor = .clear
        barHost.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(barHost)
        view.addSubview(barHost.view)
        barHost.didMove(toParent: self)
        // Нижний край панели = min(верх клавиатуры + высота полосы, низ safe area): два верхних предела и слабая «тяга» вниз.
        let spaces = FeedBottomBar.spacesHeight
        let pull = barHost.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        pull.priority = .defaultLow
        NSLayoutConstraint.activate([
            barHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            barHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barHost.view.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: spaces),
            barHost.view.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),
            pull,
            fadeHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fadeHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fadeHost.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            fadeHost.view.topAnchor.constraint(equalTo: barHost.view.topAnchor, constant: -40),
        ])
        view.bringSubviewToFront(barHost.view)
    }

    private func add(_ host: UIViewController) {
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Отступ ленты — от верха панели до низа экрана (панель + клавиатура), минус штатный нижний safe area.
        let inset = max(0, view.bounds.height - barHost.view.frame.minY - view.safeAreaInsets.bottom)
        if feedHost.additionalSafeAreaInsets.bottom != inset {
            feedHost.additionalSafeAreaInsets.bottom = inset
        }
        // Тянуть панель вниз тоже закрывает клавиатуру.
        view.keyboardLayoutGuide.keyboardDismissPadding = barHost.view.bounds.height - FeedBottomBar.spacesHeight
    }
}

/// Нижняя панель: поле ввода и полоса Spaces. Фокус поля живёт здесь и отражается в `FeedModel.typing`.
struct FeedBottomBar: View {
    /// Полоса Spaces 40 pt + отступ снизу 4 pt (как раньше).
    static let spacesHeight: CGFloat = 52 // 8 (зазор) + 40 + 4
    let model: FeedModel
    let workspaces: [Workspace]
    var onSend: () -> Void
    var onExpand: () -> Void
    var onSelect: (Int) -> Void
    var onRename: (Workspace) -> Void
    var onSettings: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 8) {
            // К старым карточкам поле чуть сжимается: на 30 pt с боков и на 6 pt сверху.
            let compact = model.spacesCollapsed && !model.typing
            Composer(text: $model.draft, focused: $focused, compact: compact, onSend: onSend, onExpand: onExpand)
                .padding(.horizontal, compact ? 46 : 16)
                // Сжатое поле на 6 pt ниже — добираем сверху: высота панели не меняется.
                .padding(.top, compact ? 6 : 0)
                .animation(.snappy, value: compact)
            // Полоса всегда в иерархии (высота панели постоянна); при клавиатуре её закрывает сама клавиатура.
            SpacesBar(workspaces: workspaces, slot: $model.slot, collapsed: model.spacesCollapsed,
                      onExpand: { withAnimation(.snappy) { model.spacesCollapsed = false } },
                      onRename: onRename, onSettings: onSettings, onSelect: onSelect)
        }
        .padding(.bottom, 4)
        .animation(.snappy, value: model.spacesCollapsed)
        .onChange(of: focused) { _, f in model.typing = f } // без своей анимации: панель едет только в анимации клавиатуры
    }
}
