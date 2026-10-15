import AppKit
// usage: sym2svg <out.json> <name>...  → {name: {"w":..,"h":..,"d":"M ..."}} ; CGPath символа, ось Y развёрнута вниз
var result: [String: [String: Any]] = [:]
for name in CommandLine.arguments.dropFirst(2) {
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let rep = img.representations.first,
          let glyph = rep.value(forKey: "vectorGlyph") as? NSObject,
          let unmanaged = glyph.perform(NSSelectorFromString("CGPath")) else { print("missing \(name)"); continue }
    let path = unmanaged.takeUnretainedValue() as! CGPath
    let b = path.boundingBoxOfPath
    var d = ""
    func p(_ pt: CGPoint) -> String { String(format: "%.2f %.2f", pt.x - b.minX, b.maxY - pt.y) }
    path.applyWithBlock { el in
        let e = el.pointee, pts = e.points
        switch e.type {
        case .moveToPoint: d += "M \(p(pts[0])) "
        case .addLineToPoint: d += "L \(p(pts[0])) "
        case .addQuadCurveToPoint: d += "Q \(p(pts[0])) \(p(pts[1])) "
        case .addCurveToPoint: d += "C \(p(pts[0])) \(p(pts[1])) \(p(pts[2])) "
        case .closeSubpath: d += "Z "
        @unknown default: break
        }
    }
    result[name] = ["w": b.width, "h": b.height, "d": d.trimmingCharacters(in: .whitespaces)]
    print("ok \(name) \(Int(b.width))×\(Int(b.height)) \(d.count) chars")
}
let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
