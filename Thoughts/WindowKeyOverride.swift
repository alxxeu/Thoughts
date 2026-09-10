import AppKit
import ObjectiveC

/// Обычный (не NSPanel) NSWindow без `.titled` в styleMask по умолчанию не
/// может стать key window — а без этого невозможен ввод текста (событие
/// клавиатуры вообще не доходит до first responder), хотя мышь продолжает
/// работать нормально, потому что hit-testing и drag-жесты этого не
/// требуют. Ровно это ломало ввод текста в Desktop Overlay после того, как
/// `.titled` сняли для устранения зазора под menu bar (см. ContentView).
///
/// SwiftUI создаёт окно само, подклассить его напрямую нельзя — подменяем
/// canBecomeKey/canBecomeMain через Objective-C runtime прямо на классе
/// конкретного окна (class_replaceMethod, не method_setImplementation на
/// найденном через наследование методе) — это затрагивает только сам класс
/// SwiftUI-окна, не саму NSWindow и не другие окна (Settings, QuitGuard).
func allowWindowToBecomeKey(_ window: NSWindow) {
    let windowClass: AnyClass = type(of: window)

    let trueIMP: @convention(block) (AnyObject) -> Bool = { _ in true }
    let imp = imp_implementationWithBlock(trueIMP)

    class_replaceMethod(windowClass, #selector(getter: NSWindow.canBecomeKey), imp, "c@:")
    class_replaceMethod(windowClass, #selector(getter: NSWindow.canBecomeMain), imp, "c@:")
}
