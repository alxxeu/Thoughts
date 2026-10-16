import SwiftUI

/// Цвета iPhone-версии (тёмная тема, docs/ios/DESIGN-SYSTEM.md).
enum Theme {
    /// Фиолетовый акцент приложения (Р18).
    static let accent = Color(red: 0.42, green: 0.36, blue: 0.96)
    static let text = Color.white.opacity(0.88)
    static let secondary = Color.white.opacity(0.55)
    /// Мягкий градиент под стеклом карточек (bg/top → bg/bottom).
    static let background = LinearGradient(
        colors: [Color(red: 0.098, green: 0.106, blue: 0.180), Color(red: 0.165, green: 0.114, blue: 0.200)],
        startPoint: .top, endPoint: .bottom
    )
    static let cardRadius: CGFloat = 16
}
