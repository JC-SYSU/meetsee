import AppKit
import CoreText

// Approved two-line bilingual lockup with a restrained satin-green ampersand.
// Outlined typography plus the same transparent mark used by the app icon.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
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

let title = placed(lettering("觅见", font: "STSongti-SC-Bold", size: 72), x: 190, y: 76, height: 42)
let meet = placed(lettering("Meet", font: "AvenirNext-Regular", size: 48), x: title.boundingBoxOfPath.maxX + 18, y: 79, height: 28)
let amp = placed(lettering("&", font: "SnellRoundhand", size: 60), x: meet.boundingBoxOfPath.maxX + 4, y: 78, height: 30)
let see = placed(lettering("See", font: "AvenirNext-Regular", size: 48), x: amp.boundingBoxOfPath.maxX + 4, y: 79, height: 28)
let motto = placed(lettering("所觅，即所见。", font: "STSongti-SC-Regular", size: 22), x: 190, y: 43, height: 14)
let english = placed(lettering("Meet it. That's it.", font: "AvenirNext-Regular", size: 18), x: motto.boundingBoxOfPath.maxX + 18, y: 44, height: 11)
let imageURL = output.appendingPathComponent("BrandMark.png")
let image = NSImage(contentsOf: imageURL)!
let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let imageData = try Data(contentsOf: imageURL)
let page = CGRect(x: 0, y: 0, width: 520, height: 160)
for dark in [false, true] {
    let ink = dark ? "#EBECE7" : "#292D29"
    let sage = dark ? "#B7CAA7" : "#708666"
    let secondary = dark ? "#BFC5BB" : "#70796C"
    let items: [(CGPath,String)] = [(title,ink),(meet,ink),(amp,sage),(see,ink),(motto,secondary),(english,secondary)]
    let name = dark ? "AboutBrand-dark" : "AboutBrand-light"
    let data = NSMutableData()
    var box = page
    let pdf = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
    pdf.beginPDFPage(nil)
    pdf.draw(cgImage, in: CGRect(x: 0, y: -10, width: 180, height: 180))
    var svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 520 160\"><title>觅见 Meet&amp;See — 所觅，即所见。</title><image x=\"0\" y=\"-10\" width=\"180\" height=\"180\" href=\"data:image/png;base64,\(imageData.base64EncodedString())\"/><g transform=\"translate(0 160) scale(1 -1)\">"
    for (index, item) in items.enumerated() {
        let (path, hex) = item
        if index == 2 {
            let colors = dark ? ["#819574", "#B0C5A0", "#D5E1CA", "#B3C7A3"] : ["#566C4E", "#7D9270", "#B4C5A5", "#829775"]
            let stops: [CGFloat] = [0, 0.42, 0.78, 1]
            let cgColors = colors.map { hex -> CGColor in
                let v = UInt32(hex.dropFirst(), radix: 16)!
                return CGColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
            }
            let rect = path.boundingBoxOfPath
            let start = CGPoint(x: rect.midX - 3, y: rect.minY)
            let end = CGPoint(x: rect.midX + 3, y: rect.maxY)
            pdf.saveGState(); pdf.addPath(path); pdf.clip()
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: cgColors as CFArray, locations: stops)!
            pdf.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            pdf.restoreGState()
            svg += "<defs><linearGradient id=\"sage-satin\" gradientUnits=\"userSpaceOnUse\" x1=\"\(start.x)\" y1=\"\(start.y)\" x2=\"\(end.x)\" y2=\"\(end.y)\">"
            for (stop, color) in zip(stops, colors) { svg += "<stop offset=\"\(stop)\" stop-color=\"\(color)\"/>" }
            svg += "</linearGradient></defs><path fill=\"url(#sage-satin)\" d=\"\(svgPath(path))\"/>"
            continue
        }
        let v = UInt32(hex.dropFirst(), radix:16)!
        pdf.setFillColor(CGColor(red:CGFloat((v >> 16) & 255)/255, green:CGFloat((v >> 8) & 255)/255, blue:CGFloat(v & 255)/255, alpha:1))
        pdf.addPath(path); pdf.fillPath()
        svg += "<path fill=\"\(hex)\" d=\"\(svgPath(path))\"/>"
    }
    pdf.endPDFPage(); pdf.closePDF()
    try (data as Data).write(to: output.appendingPathComponent(name + ".pdf"))
    try (svg + "</g></svg>").write(to: output.appendingPathComponent(name + ".svg"), atomically:true, encoding:.utf8)
}
print("Exported light/dark settings lockups")
