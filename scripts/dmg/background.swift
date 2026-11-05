// Фон окна установщика DMG: звёздное небо в духе Spoiler/Lock, стрелка между иконками и подпись.
//   swift background.swift <папка для результата>
// Кладёт background.png (660×400) и background@2x.png (1320×800, 144 dpi — то же окно, но чётче на Retina).
import AppKit

let width: CGFloat = 660, height: CGFloat = 400
// Центры иконок в окне (точки, от левого верха): приложение слева, Applications справа.
let iconY: CGFloat = 190, appX: CGFloat = 180, folderX: CGFloat = 480

func render(scale: CGFloat) -> Data {
    let pixelsW = Int(width * scale), pixelsH = Int(height * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsW, pixelsHigh: pixelsH, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height) // 144 dpi у @2x
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: height); ctx.scaleBy(x: 1, y: -1) // координаты от левого верха, как у Finder

    // Небо: тёмный сине-фиолетовый градиент, светлее к центру.
    let space = CGColorSpaceCreateDeviceRGB()
    let sky = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.07, green: 0.07, blue: 0.16, alpha: 1),
        CGColor(red: 0.12, green: 0.11, blue: 0.27, alpha: 1)
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 0), end: CGPoint(x: width, y: height), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.35, green: 0.3, blue: 0.7, alpha: 0.28),
        CGColor(red: 0.35, green: 0.3, blue: 0.7, alpha: 0)
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: width / 2, y: iconY), startRadius: 0,
                           endCenter: CGPoint(x: width / 2, y: iconY), endRadius: 320, options: [])

    // Звёзды: детерминированно, та же «хэш-синусная» схема, что в StarFieldCanvas. Фон показывается
    // в Finder 1:1 (на Retina — растянутым вдвое), поэтому звёзды — целые пиксели, без размытия.
    for i in 0..<150 {
        let s1 = sin(Double(i) * 12.9898 + 1.0) * 43758.5453, s2 = cos(Double(i) * 78.2330 + 2.0) * 43758.5453
        let s3 = sin(Double(i) * 45.1640 + 3.0) * 12345.6789
        let x = floor((s1 - floor(s1)) * Double(width)), y = floor((s2 - floor(s2)) * Double(height))
        let size: Double = (s3 - floor(s3)) > 0.82 ? 3 : 2
        let alpha = 0.35 + (s2 - floor(s2)) * 0.5
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
    }

    // Стрелка между иконками: чёткая линия 3 px по целым пикселям, без свечения (оно на Retina расплывается).
    let from = (appX + 92).rounded(), to = (folderX - 92).rounded(), lineY = iconY.rounded() + 0.5
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    ctx.setLineWidth(3); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: from, y: lineY)); ctx.addLine(to: CGPoint(x: to, y: lineY))
    ctx.move(to: CGPoint(x: to - 14, y: lineY - 12)); ctx.addLine(to: CGPoint(x: to, y: lineY)); ctx.addLine(to: CGPoint(x: to - 14, y: lineY + 12))
    ctx.strokePath()

    // Светлые плашки под подписями иконок: Finder рисует подписи чёрным, на тёмном небе их не прочесть.
    let labelY = iconY + 82
    for x in [appX, folderX] {
        let pill = CGRect(x: (x - 56).rounded(), y: (labelY - 11).rounded(), width: 112, height: 22)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.88))
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 11, cornerHeight: 11, transform: nil))
        ctx.fillPath()
    }

    // Подпись под стрелкой.
    ctx.saveGState()
    ctx.translateBy(x: 0, y: height); ctx.scaleBy(x: 1, y: -1) // вернуть обычные координаты для текста
    let text = NSAttributedString(string: "Drag to install", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .bold),
        .foregroundColor: NSColor(white: 1, alpha: 0.9)
    ])
    let size = text.size()
    text.draw(at: NSPoint(x: (width - size.width) / 2, y: height - iconY - 34 - size.height / 2))
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try render(scale: 1).write(to: out.appendingPathComponent("background.png"))
try render(scale: 2).write(to: out.appendingPathComponent("background@2x.png"))
