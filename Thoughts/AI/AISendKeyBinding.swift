import Foundation

/// Какое сочетание клавиш отправляет запрос в панели Ask AI, а какое
/// переносит строку — настраивается в Settings → AI, см. AISettingsView.
enum AISendKeyBinding: String, CaseIterable, Identifiable, Codable {
    case returnSends
    case shiftReturnSends

    var id: String { rawValue }

    var title: String {
        switch self {
        case .returnSends: return "Return"
        case .shiftReturnSends: return "Shift+Return"
        }
    }

    var description: String {
        switch self {
        case .returnSends: return "Return sends your message; Shift+Return adds a new line."
        case .shiftReturnSends: return "Shift+Return sends your message; Return adds a new line."
        }
    }
}
