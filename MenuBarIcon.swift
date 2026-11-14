import AppKit

/// A small-size, monochrome version of Meet&See's intersecting circles.
/// Template rendering lets macOS choose contrast for the actual menu bar.
enum MenuBarIcon {
    static let size = NSSize(width: 22, height: 18)
    static func make() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            let radius: CGFloat = 5.75
            let left = NSPoint(x: 7.25, y: 9), right = NSPoint(x: 14.75, y: 9)
            NSColor.black.setFill(); NSColor.black.setStroke()
            for center in [left, right] {
                let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                       width: radius * 2, height: radius * 2))
                ring.lineWidth = 1.4; ring.stroke()
            }
            // The solid lens is the brand's "meeting" point. No handle, text,
            // baked colour, shadow or tiny decorative detail at menu-bar scale.
            let angle = acos((right.x - left.x) / (radius * 2)) * 180 / .pi
            let lens = NSBezierPath()
            lens.appendArc(withCenter: left, radius: radius, startAngle: -angle, endAngle: angle)
            lens.appendArc(withCenter: right, radius: radius, startAngle: 180 - angle, endAngle: 180 + angle)
            lens.close(); lens.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "觅见"
        return image
    }
}
