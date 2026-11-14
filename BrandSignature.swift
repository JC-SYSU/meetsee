import AppKit

final class BrandSignatureView: NSView {
    private let light: NSImage
    private let dark: NSImage
    private var shown = false
    static func shouldShow(query: String, scanning: Bool) -> Bool {
        query.isEmpty && !scanning
    }
    static func signatureFrame(width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(x: width - 136, y: height + 14, width: 136, height: 23.71)
    }
    init(resources: URL = Bundle.main.resourceURL!) {
        light = NSImage(contentsOf: resources.appendingPathComponent("Signature-light.pdf"))!
        dark = NSImage(contentsOf: resources.appendingPathComponent("Signature-dark.pdf"))!
        super.init(frame: .zero)
        wantsLayer = true
        alphaValue = 0
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let image = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
    func update(query: String, scanning: Bool, animated: Bool) {
        let next = Self.shouldShow(query: query, scanning: scanning)
        guard next != shown else { return }
        shown = next
        let alpha: CGFloat = next ? 0.48 : 0
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = next ? 0.18 : 0.10
                animator().alphaValue = alpha
            }
        } else {
            layer?.removeAllAnimations()
            alphaValue = alpha
        }
    }
}
