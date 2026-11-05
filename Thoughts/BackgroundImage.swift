import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Свои обои для фона окна: картинку выбирают в NSOpenPanel (права на запись экрана не
/// нужны), уменьшают до 4K и копируют в папку данных — оригинал приложению не нужен.
final class BackgroundImageStore {
    static let shared = BackgroundImageStore()

    private static let maxPixelSize = 3840
    private var cached: NSImage?

    private var folder: URL { BoardStore.dataFolder.appendingPathComponent("Backgrounds", isDirectory: true) }
    var fileURL: URL { folder.appendingPathComponent("background.jpg") }
    var hasImage: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    var image: NSImage? {
        if cached == nil { cached = NSImage(contentsOf: fileURL) }
        return cached
    }

    /// Копия выбранной картинки (уменьшенная, JPEG); бросает, если файл не картинка.
    func save(from url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: Self.maxPixelSize
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        cached = nil
    }
}

enum BackgroundImagePicker {
    /// Диалог выбора картинки; `directory` — с какой папки начать (nil — как обычно у системы).
    /// true — картинка выбрана и сохранена.
    @discardableResult
    static func pick(startingIn directory: URL? = nil, message: String) -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = message
        panel.directoryURL = directory
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try BackgroundImageStore.shared.save(from: url)
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn\u{2019}t use this image"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return false
        }
    }

    /// Папка текущих обоев (для кнопки «Use Current Wallpaper»); nil — система не сказала.
    static var currentWallpaperFolder: URL? {
        NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }?.deletingLastPathComponent()
    }
}
