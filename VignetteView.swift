import AppKit

/// Native radial shading: 4% at the screen center, 20% at the farthest corners.
final class VignetteView: NSView {
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(starting: NSColor.black.withAlphaComponent(0.04),
                                  ending: NSColor.black.withAlphaComponent(0.20))!
        gradient.draw(in: bounds, relativeCenterPosition: .zero)
    }
}
