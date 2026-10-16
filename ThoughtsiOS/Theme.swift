import SwiftUI

/// Цвета iPhone-версии (тёмная тема, docs/ios/DESIGN-SYSTEM.md).
enum Theme {
    /// Фиолетовый акцент приложения (Р18).
    static let accent = Color(red: 0.42, green: 0.36, blue: 0.96)
    static let text = Color.white.opacity(0.88)
    static let secondary = Color.white.opacity(0.55)
    /// Ровный тёмно-серый фон (темнее макетов — проба 2026-10-16).
    static let background = Color(red: 0.07, green: 0.07, blue: 0.075)
    /// Затухания у краёв экрана — чуть темнее фона.
    static let fade = Color(red: 0.025, green: 0.025, blue: 0.028)
    static let cardRadius: CGFloat = 24
}
