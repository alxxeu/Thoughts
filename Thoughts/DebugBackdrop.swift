#if DEBUG
import SwiftUI
import AppKit

/// Временное сравнение фонов окна (только Debug): швы в живом блюре
/// (BACKLOG «прямоугольные швы») — проверяем на глаз, приглушает ли их
/// другой материал или плотный тон. Меню Debug → Background. После выбора
/// удалить вместе с меню.
@Observable
final class DebugBackdrop {
    static let shared = DebugBackdrop()

    enum Option: String, CaseIterable, Identifiable {
        case hudWindow, ultraThin, thin, regular, thick, ultraThick, flatTint, wallpaperSnapshot

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hudWindow: return "HUD Window (current)"
            case .ultraThin: return "Ultra Thin Material"
            case .thin: return "Thin Material"
            case .regular: return "Regular Material"
            case .thick: return "Thick Material"
            case .ultraThick: return "Ultra Thick Material"
            case .flatTint: return "Flat Tint (no blur)"
            case .wallpaperSnapshot: return "Wallpaper Snapshot (Screen Recording)"
            }
        }
    }

    private static let key = "debug.backdrop"

    var option: Option {
        didSet { UserDefaults.standard.set(option.rawValue, forKey: Self.key) }
    }

    private init() {
        option = UserDefaults.standard.string(forKey: Self.key).flatMap(Option.init) ?? .hudWindow
    }
}

/// Фон окна по выбору в Debug → Background.
struct DebugBackdropView: View {
    private let backdrop = DebugBackdrop.shared

    var body: some View {
        switch backdrop.option {
        case .hudWindow: VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
        case .ultraThin: Rectangle().fill(.ultraThinMaterial)
        case .thin: Rectangle().fill(.thinMaterial)
        case .regular: Rectangle().fill(.regularMaterial)
        case .thick: Rectangle().fill(.thickMaterial)
        case .ultraThick: Rectangle().fill(.ultraThickMaterial)
        case .flatTint: Color(nsColor: .windowBackgroundColor).opacity(0.85)
        case .wallpaperSnapshot: WallpaperSnapshotBackground()
        }
    }
}

struct DebugBackdropCommands: Commands {
    var body: some Commands {
        CommandMenu("Debug") {
            Picker("Background", selection: Binding(
                get: { DebugBackdrop.shared.option },
                set: { DebugBackdrop.shared.option = $0 }
            )) {
                ForEach(DebugBackdrop.Option.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
        }
    }
}
#endif
