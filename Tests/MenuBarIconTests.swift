import AppKit
@main struct MenuBarIconTests {
    static func main() throws {
        let icon = MenuBarIcon.make()
        precondition(icon.isTemplate && icon.size == NSSize(width: 22, height: 18))
        precondition(icon.accessibilityDescription == "觅见")
        for scale in [1, 2, 3] {
            let width = 22 * scale, height = 18 * scale
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = icon.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            // Template pixels, not the system's menu-bar tint.
            let pixels = icon.copy() as! NSImage; pixels.isTemplate = false
            pixels.draw(in: NSRect(origin: .zero, size: icon.size))
            NSGraphicsContext.restoreGraphicsState()
            func alpha(_ x: Int, _ y: Int) -> CGFloat { rep.colorAt(x: x, y: y)!.alphaComponent }
            for x in 0..<width { precondition(alpha(x, 0) == 0 && alpha(x, height - 1) == 0) }
            precondition(alpha(11 * scale, 9 * scale) > 0.95) // Solid meeting point.
            precondition(alpha(4 * scale, 9 * scale) < 0.05) // Open left circle.
            precondition(alpha(18 * scale, 9 * scale) < 0.05) // Open right circle.
            let path = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("menu-icon-\(scale)x.png")
            try rep.representation(using: .png, properties: [:])!.write(to: path)
        }
        print("PASS: distinct brand circles, native template/accessibility, 1x/2x/3x render, clear ring apertures and transparent padding")
    }
}
