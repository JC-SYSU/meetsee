import AppKit

/// A fixed-brand lockup, independent of the user's interface font.
final class BrandAboutView: NSView {
    private let light: NSImage
    private let dark: NSImage
    init(frame: NSRect, resources: URL = Bundle.main.resourceURL!) {
        light = NSImage(contentsOf: resources.appendingPathComponent("AboutBrand-light.pdf"))!
        dark = NSImage(contentsOf: resources.appendingPathComponent("AboutBrand-dark.pdf"))!
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("觅见 Meet&See。所觅，即所见。Meet it. That's it.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    var artworkRect: NSRect {
        let scale = min(bounds.width / light.size.width, bounds.height / light.size.height)
        let size = NSSize(width: light.size.width * scale, height: light.size.height * scale)
        return NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        let image = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        image.draw(in: artworkRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
}
