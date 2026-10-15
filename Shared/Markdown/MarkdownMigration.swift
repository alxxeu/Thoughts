#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Разовый перевод текста карточки из старого формата (обычная строка +
/// архив NSAttributedString в formattingData) в Markdown. Применяется к
/// карточкам с диска, к записям iCloud со старых версий и к импорту
/// старых бэкапов — везде, где textFormat < markdownFormat.
///
/// Переносится то, что есть в Markdown: жирный, курсив, зачёркивание,
/// подчёркивание, ссылки, списки "• " → "- ", разделитель → "---".
/// Цвет, шрифт и размер фрагментов в Markdown не хранятся и теряются.
enum MarkdownMigration {
    /// Версия формата текста: 1 — старый (text + formattingData), 2 — Markdown.
    static let legacyFormat = 1
    static let markdownFormat = 2

    static func markdown(text: String, formattingData: Data?) -> String {
        let body: String
        if let attributed = attributedString(from: formattingData), attributed.string == text {
            body = markdown(from: attributed)
        } else {
            body = escaped(text).replacingOccurrences(of: "\u{FFFC}", with: "---")
        }
        return body
            .components(separatedBy: "\n")
            .map { $0.hasPrefix("\u{2022} ") ? "- " + $0.dropFirst(2) : $0 }
            .joined(separator: "\n")
    }

    /// Обычный текст → Markdown, который выглядит так же: экранируются только
    /// символы, которые разбор и правда превратил бы в разметку (`2*3*4`),
    /// а одиночные `~`/`=` в адресах вроде `site.com/~me?a=b` не трогаются.
    /// shortcut: обратный слэш перед спецсимволом в старом тексте экранируется,
    /// но символ после него может образовать пару — на практике не встречается.
    static func escaped(_ text: String) -> String {
        let ns = text as NSString
        var positions = Set<Int>()
        for paragraph in MarkdownStyler.parse(text) {
            if case .heading = paragraph.block, let marker = paragraph.blockMarker {
                positions.insert(marker.location)
            }
            for marker in paragraph.markers {
                // У ссылки достаточно экранировать "[" — хвост "](url)" сам по
                // себе не разметка.
                if ns.character(at: marker.location) == closeBracket { continue }
                for index in marker.location..<NSMaxRange(marker) { positions.insert(index) }
            }
        }
        let result = NSMutableString(string: text)
        for index in positions.sorted(by: >) {
            result.insert("\\", at: index)
        }
        return result as String
    }

    private static let closeBracket = unichar(UInt8(ascii: "]"))

    private static func attributedString(from data: Data?) -> NSAttributedString? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSAttributedString.self, DividerAttachment.self],
            from: data
        ) as? NSAttributedString
    }

    private static func markdown(from attributed: NSAttributedString) -> String {
        var result = ""
        let ns = attributed.string as NSString
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            if attributes[.attachment] is DividerAttachment {
                result += "---"
                return
            }
            #if os(macOS)
            let traits = (attributes[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
            let isBold = traits.contains(.boldFontMask), isItalic = traits.contains(.italicFontMask)
            #else
            // Архив с Mac может не прочитаться на iOS — тогда выше остаётся
            // просто текст; Mac мигрирует свои карточки сам при запуске.
            let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
            let isBold = traits.contains(.traitBold), isItalic = traits.contains(.traitItalic)
            #endif
            var open = ""
            if isBold { open += "**" }
            if isItalic { open += "*" }
            if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { open += "~~" }
            if (attributes[.underlineStyle] as? Int ?? 0) != 0, attributes[.link] == nil { open += "~" }
            let close = String(open.reversed())
            let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String

            let chunk = ns.substring(with: range)
            result += chunk.components(separatedBy: "\n").map { line in
                wrap(escaped(line), open: open, close: close, link: link, original: line)
            }.joined(separator: "\n")
        }
        return result
    }

    /// Маркеры — вокруг текста без краевых пробелов: `** bold **` Markdown
    /// жирным не считает.
    private static func wrap(_ line: String, open: String, close: String, link: String?, original: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !(open.isEmpty && link == nil) else { return line }
        // Края — и пробелы, и табы: иначе табуляция в начале строки терялась.
        let leading = String(line.prefix { $0 == " " || $0 == "\t" })
        let trailing = String(String(line.reversed().prefix { $0 == " " || $0 == "\t" }).reversed())
        var core = trimmed
        // Автоссылка, где текст и есть адрес, остаётся голым адресом.
        if let link, link != original.trimmingCharacters(in: .whitespaces) {
            core = "[\(core)](\(link))"
        }
        return leading + open + core + close + trailing
    }
}

/// Разделитель в старом формате — вложение в архиве formattingData. Нужен
/// только чтобы прочитать такие архивы при миграции; сейчас разделитель —
/// строка `---` в Markdown.
final class DividerAttachment: NSTextAttachment {
    /// Без этого secure coding не читает архивы с разделителем.
    override class var supportsSecureCoding: Bool { true }
}
