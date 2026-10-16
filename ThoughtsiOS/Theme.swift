import SwiftUI

/// Цвета iPhone-версии (тёмная тема, docs/ios/DESIGN-SYSTEM.md).
enum Theme {
    /// Фиолетовый акцент приложения (Р18).
    static let accent = Color(red: 0.42, green: 0.36, blue: 0.96)
    static let text = Color.white.opacity(0.88)
    static let secondary = Color.white.opacity(0.55)
    /// Ровный тёмно-серый фон, как в макетах (доводка 2026-10-16).
    static let background = Color(red: 0.11, green: 0.11, blue: 0.118)
    /// Затухания у краёв экрана — чуть темнее фона.
    static let fade = Color(red: 0.06, green: 0.06, blue: 0.065)
    static let cardRadius: CGFloat = 16
}
