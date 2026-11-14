import AppKit
@main struct PinnedStatusBadgeTests {
    static func main() {
        _ = NSApplication.shared
        for family in ["Maple Mono NF CN", "PingFang SC", "Helvetica Neue"] {
            for title in ["旅行", "旅行计划.docx", String(repeating: "长文件名", count: 30)] {
                let name = NSTextField(labelWithString: title)
                name.font = NSFont(name: family, size: 18) ?? .systemFont(ofSize: 18)
                name.frame = NSRect(x: 60, y: 9, width: 200, height: 25)
                let frame = PinnedStatusBadge.place(after: name)
                precondition(frame.size == NSSize(width: 25, height: 13))
                precondition(abs(frame.midY - CandidateTextLayout.titleCenter(name)) < 0.001)
                precondition(frame.maxX <= 260 && name.frame.width == 168)
                precondition(frame.minX > name.frame.minX)
            }
        }
        let badge = PinnedStatusBadge(frame: NSRect(origin: .zero, size: PinnedStatusBadge.size))
        precondition(badge.hitTest(NSPoint(x: 12, y: 6)) == nil)
        precondition(badge.accessibilityLabel() == "常用置顶")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            badge.appearance = NSAppearance(named: appearance)
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 50, pixelsHigh: 26, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            let scale = NSAffineTransform(); scale.scale(by: 2); scale.concat()
            badge.effectiveAppearance.performAsCurrentDrawingAppearance { badge.draw(badge.bounds) }
            NSGraphicsContext.restoreGraphicsState()
            let color = rep.colorAt(x: 5, y: 13)!.usingColorSpace(.sRGB)!
            let expected: CGFloat = appearance == .aqua ? 62/255 : 68/255
            precondition(abs(color.redComponent - expected) < 0.02 && color.alphaComponent > 0.95)
        }
        print("PASS: pinned plaque size, title alignment, truncation reservation, fixed typography, pointer passthrough, accessibility and light/dark paint")
    }
}
