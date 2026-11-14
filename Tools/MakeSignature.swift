import AppKit
import CoreText

// Editable layout master. Exported PDF/SVG contain outlines, not runtime fonts.
// Usage: swift Tools/MakeSignature.swift Brand
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func lettering(_ text: String, font: String, size: CGFloat) -> CGPath {
    let f = CTFontCreateWithName(font as CFString, size, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: f]))
    let result = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let n = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: n), positions = [CGPoint](repeating: .zero, count: n)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
        for i in 0..<n {
            if let path = CTFontCreatePathForGlyph(f, glyphs[i], nil) {
                result.addPath(path, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
            }
        }
    }
    return result
}
func placed(_ path: CGPath, x: CGFloat, y: CGFloat, height: CGFloat? = nil) -> CGPath {
    let box = path.boundingBoxOfPath
    let scale = height.map { $0 / box.height } ?? 1
    var t = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x - box.minX * scale, ty: y - box.minY * scale)
    return path.copy(using: &t)!
}
let meet = placed(lettering("Meet", font: "AvenirNext-UltraLight", size: 80), x: 2, y: 14)
let amp = placed(lettering("&", font: "SnellRoundhand", size: 90), x: meet.boundingBoxOfPath.maxX + 6, y: 7, height: 75)
let see = placed(lettering("See", font: "AvenirNext-UltraLight", size: 80), x: amp.boundingBoxOfPath.maxX + 6, y: 14)
let radius: CGFloat = 22
let leftX = see.boundingBoxOfPath.maxX + 14
let left = CGPath(ellipseIn: CGRect(x: leftX, y: 20, width: 44, height: 44), transform: nil)
let right = CGPath(ellipseIn: CGRect(x: leftX + 26, y: 20, width: 44, height: 44), transform: nil)
// Lens intersection, with exact circular arcs; no raster texture or baked shadow.
let lens = CGMutablePath()
let theta = acos(CGFloat(13) / radius)
let c1 = CGPoint(x: leftX + radius, y: 42), c2 = CGPoint(x: leftX + 26 + radius, y: 42)
lens.addArc(center: c1, radius: radius, startAngle: -theta, endAngle: theta, clockwise: false)
lens.addArc(center: c2, radius: radius, startAngle: .pi - theta, endAngle: .pi + theta, clockwise: false)
lens.closeSubpath()
let page = CGRect(x: 0, y: 0, width: leftX + 72, height: 86)
func svgPath(_ path: CGPath) -> String {
    var d = ""
    func pair(_ p: CGPoint) -> String { String(format: "%.3f %.3f", Double(p.x), Double(p.y)) }
    path.applyWithBlock { pointer in
        let e = pointer.pointee
        switch e.type {
        case .moveToPoint: d += "M" + pair(e.points[0])
        case .addLineToPoint: d += "L" + pair(e.points[0])
        case .addQuadCurveToPoint: d += "Q" + pair(e.points[0]) + " " + pair(e.points[1])
        case .addCurveToPoint: d += "C" + pair(e.points[0]) + " " + pair(e.points[1]) + " " + pair(e.points[2])
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}
for dark in [false, true] {
    let name = dark ? "Signature-dark" : "Signature-light"
    let ink = dark ? "#E7E8E5" : "#333735"
    let sage = dark ? "#B6C9A8" : "#708666"
    let ivory = dark ? "#DBDED5" : "#C3C9BC"
    let charcoal = dark ? "#889086" : "#555E54"
    let items: [(CGPath, String)] = [(meet,ink),(amp,sage),(see,ink),(left,ivory),(right,charcoal),(lens,sage)]
    let data = NSMutableData()
    var box = page
    let pdf = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
    pdf.beginPDFPage(nil)
    var svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(page.width) \(page.height)\"><title>Meet &amp; See</title><g transform=\"translate(0 \(page.height)) scale(1 -1)\">"
    for (path, hex) in items {
        let v = UInt32(hex.dropFirst(), radix: 16)!
        pdf.setFillColor(CGColor(red: CGFloat((v >> 16) & 255)/255, green: CGFloat((v >> 8) & 255)/255, blue: CGFloat(v & 255)/255, alpha: 1))
        pdf.addPath(path); pdf.fillPath()
        svg += "<path fill=\"\(hex)\" d=\"\(svgPath(path))\"/>"
    }
    pdf.endPDFPage(); pdf.closePDF()
    try (data as Data).write(to: output.appendingPathComponent(name + ".pdf"))
    try (svg + "</g></svg>").write(to: output.appendingPathComponent(name + ".svg"), atomically: true, encoding: .utf8)
}
print("Exported outlined SVG/PDF, aspect ratio \(page.width / page.height)")
