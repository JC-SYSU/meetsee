import AppKit

// Shared by live result rows and the settings samples.
enum SelectionPaint {
    static let inverseSubtitleColor = NSColor.white.withAlphaComponent(0.72)
    static func draw(_ style: HighlightStyle, in rect: NSRect, dark: Bool, radius: CGFloat = 13) {
        let shape = ContinuousCorners.bezier(in: rect, radius: radius)
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> NSColor {
            NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        }
        let colors: (NSColor, NSColor)
        switch style {
        case .mist:
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            CeladonMaterial.image(dark: dark).draw(in: rect, from: .zero, operation: .sourceOver,
                fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
            NSGraphicsContext.restoreGraphicsState()
            return
        case .pearl:
            colors = dark ? (color(1, 253 / 255, 250 / 255, 0.07), color(1, 254 / 255, 252 / 255, 0.12)) : (color(1, 253 / 255, 250 / 255, 0.50), color(1, 254 / 255, 252 / 255, 0.84))
        case .marker:
            color(0, 47 / 255, 167 / 255, 1).setFill(); shape.fill()
            return
        case .graphite:
            color(41 / 255, 43 / 255, 46 / 255, 0.50).setFill(); shape.fill()
            return
        }
        if style == .pearl {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.06)
            shadow.shadowBlurRadius = 4; shadow.shadowOffset = NSSize(width: 0, height: -1); shadow.set()
            colors.0.setFill(); shape.fill(); NSGraphicsContext.restoreGraphicsState()
        }
        if style == .pearl {
            NSGraphicsContext.saveGraphicsState(); shape.addClip()
            let flipped = NSGraphicsContext.current?.isFlipped == true
            NSGradient(starting: colors.0, ending: colors.1)!.draw(
                from: NSPoint(x: rect.midX, y: flipped ? rect.minY : rect.maxY),
                to: NSPoint(x: rect.midX, y: flipped ? rect.maxY : rect.minY), options: [])
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSGradient(starting: colors.0, ending: colors.1)!.draw(in: shape, angle: 90)
        }
        if style == .pearl {
            NSColor.white.withAlphaComponent(dark ? 0.13 : 0.65).setStroke(); shape.lineWidth = 0.5; shape.stroke()
        }

    }

}

// Static CPU translation of light-lab.html's thin-medium shader. Two small
// textures are generated once, shared by rows, previews and swatches. There is
// no display link, GPU loop or screen capture. The underlying native glass is
// participates via source-over compositing; this is a backdrop-responsive
// approximation, not live linear-light transmission or a screen texture.
enum CeladonMaterial {
    static let lightStrength = 1.6
    static func opacity(dark: Bool) -> Double { dark ? 0.57 : 0.50 }
    private static let light = makeImage(dark: false)
    private static let dark = makeImage(dark: true)
    static func image(dark: Bool) -> NSImage { dark ? self.dark : light }

    private static func makeImage(dark: Bool) -> NSImage {
        let width = 256, height = 64
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bitmapFormat: .alphaNonpremultiplied,
            bytesPerRow: width * 4, bitsPerPixel: 32)!
        let pixels = bitmap.bitmapData!
        // SDR companion to the Metal celadon palette: blue-green porcelain
        // body, not electric cyan. Light geometry and strength stay unchanged.
        let background: [Double] = dark ? [0.18, 0.23, 0.25] : [0.953, 0.962, 0.950]
        let extinction: [Double] = [0.90, 0.66, 0.62]
        let scatter: [Double] = [0.075, 0.16, 0.18]
        for y in 0..<height {
            let v = (Double(y) + 0.5) / Double(height)
            let thickness = 0.66 + 0.13 * sin(v * .pi)
            for x in 0..<width {
                let u = (Double(x) + 0.5) / Double(width)
                let nx = 0.025 * (0.5 - u), ny = 0.07 * (0.5 - v)
                let normalLength = sqrt(nx * nx + ny * ny + 1)
                var irradiance = 0.0
                for sample in 0..<4 {
                    let dx = -0.5 + Double(sample) * 0.65 - u
                    let dy = -1.2 - v * 0.38, dz = 1.6
                    let distanceSquared = dx * dx + dy * dy + dz * dz
                    let cosine = max(0, (nx * dx + ny * dy + dz) / (normalLength * sqrt(distanceSquared)))
                    irradiance += cosine / (1 + distanceSquared * 0.12)
                }
                irradiance *= 0.25
                for channel in 0..<3 {
                    let transmitted = pow(background[channel], 2.2) * exp(-extinction[channel] * thickness)
                    let scattered = scatter[channel] * 0.90 * (1 - exp(-thickness * 1.7)) * irradiance * lightStrength
                    // Dark appearance keeps white text legible, using the same
                    // light field at reduced exposure rather than a pale sticker.
                    let energy = transmitted + scattered * (dark ? 0.28 : 1)
                    let mapped = energy / (1 + max(energy - 0.83, 0) * 0.7)
                    let encoded = pow(min(1, max(0, mapped)), 1 / 2.2)
                    // Remove the reference backdrop from the baked result before
                    // compositing. Merely lowering opacity would wash out the light.
                    // Standard source-over cannot exactly reproduce wavelength-
                    // dependent transmission; near-white channels may gamut-clip.
                    let alpha = opacity(dark: dark)
                    let foreground = min(1, max(0, (encoded - (1 - alpha) * background[channel]) / alpha))
                    pixels[y * bitmap.bytesPerRow + x * 4 + channel] = UInt8((foreground * 255).rounded())
                }
                pixels[y * bitmap.bytesPerRow + x * 4 + 3] = UInt8((opacity(dark: dark) * 255).rounded())
            }
        }
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap.retagging(with: .sRGB) ?? bitmap)
        return image
    }
}

private final class ThemeChoiceCell: NSButtonCell {
    override func hitTest(for event: NSEvent, in cellFrame: NSRect, of controlView: NSView) -> NSCell.HitResult {
        // The custom surface spans the full frame, not the stock radio glyph/title.
        guard isEnabled, cellFrame.contains(controlView.convert(event.locationInWindow, from: nil)) else { return [] }
        return [.contentArea, .trackableArea]
    }
}

/// Native button semantics with a quiet, swatch-led appearance.
final class ThemeChoiceButton: NSButton {
    let style: HighlightStyle
    private var hover = false
    private var tracking: NSTrackingArea?
    init(style: HighlightStyle, frame: NSRect) {
        self.style = style
        super.init(frame: frame)
        cell = ThemeChoiceCell(textCell: "")
        switch style {
        case .mist: title = "天青"
        case .pearl: title = "柔白"
        case .marker: title = "蓝标"
        case .graphite: title = "石墨"
        }
        toolTip = style.detail
        setButtonType(.radio); isBordered = false
        font = .systemFont(ofSize: 13)
        focusRingType = .exterior
        setAccessibilityLabel(style.title)
        setAccessibilityHelp(style.detail)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func drawFocusRingMask() {
        ContinuousCorners.bezier(in: bounds.insetBy(dx: 2, dy: 2), radius: 8).fill()
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let selected = state == .on
        let shape = ContinuousCorners.bezier(in: bounds.insetBy(dx: 2, dy: 2), radius: 8)
        // Match the original HTML study: #293b4d selected, #fff9 idle.
        let ink = NSColor(srgbRed: 41 / 255, green: 59 / 255, blue: 77 / 255, alpha: 1)
        let fill = selected ? ink : NSColor.white.withAlphaComponent(dark ? (hover ? 0.12 : 0.07) : (hover ? 0.85 : 0.60))
        fill.setFill(); shape.fill()
        let border = dark ? NSColor.white.withAlphaComponent(selected ? 0.25 : 0.17)
            : (selected ? ink : NSColor(srgbRed: 211 / 255, green: 216 / 255, blue: 220 / 255, alpha: 1))
        border.setStroke(); shape.lineWidth = 1; shape.stroke()
        if selected && hover && isEnabled {
            NSColor.white.withAlphaComponent(0.12).setFill(); shape.fill()
        }
        if isHighlighted {
            (selected ? NSColor.white.withAlphaComponent(0.09) : NSColor.labelColor.withAlphaComponent(0.06)).setFill()
            shape.fill()
        }
        let swatch = NSRect(x: 12, y: (bounds.height - 20) / 2, width: 22, height: 20)
        NSGraphicsContext.saveGraphicsState()
        ContinuousCorners.bezier(in: swatch, radius: 6).addClip()
        (dark ? NSColor(white: 0.2, alpha: 1) : NSColor(srgbRed: 0.94, green: 0.96, blue: 0.96, alpha: 1)).setFill()
        swatch.fill()
        SelectionPaint.draw(style, in: swatch, dark: dark, radius: 6)
        NSGraphicsContext.restoreGraphicsState()
        let textColor = selected ? NSColor.white : (dark ? NSColor.labelColor : NSColor(srgbRed: 66 / 255, green: 75 / 255, blue: 85 / 255, alpha: 1))
        let attrs: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: textColor]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: 44, y: (bounds.height - size.height) / 2), withAttributes: attrs)
        if selected {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.9)]
            let mark = "✓" as NSString
            let size = mark.size(withAttributes: attrs)
            mark.draw(at: NSPoint(x: bounds.width - 24, y: (bounds.height - size.height) / 2), withAttributes: attrs)
        }
    }
}

final class SettingsCanvas: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (dark ? NSColor.windowBackgroundColor : NSColor(srgbRed: 0.957, green: 0.957, blue: 0.945, alpha: 1)).setFill()
        bounds.fill()
    }
}

func searchPanelOrigin(screen: NSRect, visible: NSRect, margin: CGFloat, width: CGFloat = 720) -> NSPoint {
    NSPoint(x: screen.midX - width / 2 - margin, y: visible.midY + visible.height * 0.12 - 40 - margin)
}

final class StylePreview: NSView {
    var style: HighlightStyle = .mist { didSet { hdr.material = style == .pearl ? .pearl : (style == .marker ? .marker : .celadon); hdr.active = style != .graphite; foreground.needsDisplay = true } }
    var whiteOpacity: CGFloat = 0
    var glassTintStrength: CGFloat = 0 {
        didSet { updateNativeGlassTint() }
    }
    var fontName: String = "Maple Mono NF CN" { didSet { foreground.needsDisplay = true } }
    private let hdr = HDRSelectionView(frame: .zero)
    private let foreground = PreviewForeground(frame: .zero)
    private var nativeGlass: NSGlassEffectView?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds.insetBy(dx: 20, dy: 18))
            glass.style = .regular
            glass.cornerRadius = 19
            glass.autoresizingMask = [.width, .height]
            nativeGlass = glass
            addSubview(glass)
        } else {
            nativeGlass = nil
        }
        addSubview(hdr)
        hdr.onPresentationChange = { [weak self] in self?.foreground.needsDisplay = true }
        hdr.active = style == .mist
        foreground.preview = self
        foreground.frame = bounds
        foreground.autoresizingMask = [.width, .height]
        addSubview(foreground)
        updateNativeGlassTint()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func layout() {
        super.layout()
        nativeGlass?.frame = bounds.insetBy(dx: 20, dy: 18)
        hdr.frame = NSRect(x: 30, y: 60, width: bounds.width - 60, height: 38)
    }
    private func updateNativeGlassTint() {
        if #available(macOS 26.0, *), let glass = nativeGlass {
            glass.tintColor = glassTintStrength <= 0 ? nil : NSColor.white.withAlphaComponent(glassTintStrength)
            glass.needsDisplay = true
        }
    }
    // Keep effects above the glass but below all sample content, as in the live panel.
    func insertMotion(_ motion: NSView) {
        motion.frame = bounds.insetBy(dx: 20, dy: 18)
        addSubview(motion, positioned: .below, relativeTo: foreground)
    }
    func positionMotion(_ motion: NSView, background: Bool) {
        motion.removeFromSuperview()
        motion.frame = background ? bounds : bounds.insetBy(dx: 20, dy: 18)
        addSubview(motion, positioned: .below, relativeTo: background ? (nativeGlass ?? foreground) : foreground)
    }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let backdrop = ContinuousCorners.bezier(in: bounds, radius: 16)
        NSGradient(starting: dark ? NSColor(srgbRed: 0.22, green: 0.27, blue: 0.30, alpha: 1) : NSColor(srgbRed: 0.88, green: 0.88, blue: 0.82, alpha: 1), ending: dark ? NSColor(srgbRed: 0.18, green: 0.24, blue: 0.31, alpha: 1) : NSColor(srgbRed: 0.77, green: 0.84, blue: 0.88, alpha: 1))!.draw(in: backdrop, angle: 35)
        if nativeGlass == nil {
            let glass = ContinuousCorners.bezier(in: bounds.insetBy(dx: 20, dy: 18), radius: 19)
            (dark ? NSColor(srgbRed: 0.16, green: 0.19, blue: 0.22, alpha: 0.90) : NSColor(srgbRed: 0.97, green: 0.98, blue: 0.99, alpha: 0.84)).setFill(); glass.fill()
            // White-overlay preview disabled: tintColor is evaluated on the actual panel.
            // NSColor.white.withAlphaComponent(whiteOpacity).setFill(); glass.fill()
        }
    }
    fileprivate func drawForeground() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor, _ weight: NSFont.Weight = .regular) {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            (value as NSString).draw(in: NSRect(x: x, y: y, width: bounds.width - x - 32, height: size + 10), withAttributes: [.font: (NSFontManager.shared.font(withFamily: fontName, traits: [], weight: weight == .regular ? 5 : 9, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)), .foregroundColor: color, .paragraphStyle: paragraph])
        }
        text("旅行", 36, 27, 20, .labelColor)
        if style == .graphite || !hdr.hasPresentedFrame {
            SelectionPaint.draw(style, in: NSRect(x: 30, y: 60, width: bounds.width - 60, height: 38), dark: dark)
        }
        let icon = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)!.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemCyan]))
        for (index, name) in ["旅行", "旅行照片"].enumerated() {
            let y = CGFloat(64 + index * 42)
            icon?.draw(in: NSRect(x: 40, y: y + 3, width: 24, height: 24))
            let inverse = (style == .marker || style == .graphite) && index == 0
            text(name, 76, y, 13, inverse ? .white : .labelColor, .medium)
            text("~/Documents/" + name, 76, y + 18, 10, inverse ? SelectionPaint.inverseSubtitleColor : .secondaryLabelColor)
        }
    }
}

private final class PreviewForeground: NSView {
    weak var preview: StylePreview?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { preview?.drawForeground() }
}

// A native, non-interactive white layer below the search controls.
final class WhiteOverlayView: NSView {
    var opacity: CGFloat = 0 { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(opacity).setFill()
        ContinuousCorners.bezier(in: bounds, radius: 22).fill()
    }
}

/// The row owns selection state; the content keeps typography/layout intact.
final class CandidateCellView: NSTableCellView {
    var subtitleField: NSTextField?
    var onContrastChange: ((Bool) -> Void)?
    override var isFlipped: Bool { true }
    func applySelection(style: HighlightStyle, selected: Bool) {
        let inverse = selected && (style == .marker || style == .graphite)
        textField?.textColor = inverse ? .white : .labelColor
        subtitleField?.textColor = inverse ? SelectionPaint.inverseSubtitleColor : .secondaryLabelColor
        imageView?.contentTintColor = inverse ? .white : nil
        onContrastChange?(inverse)
    }
}

final class HighlightRow: NSTableRowView {
    private let hdr = HDRSelectionView(frame: .zero)
    var style: HighlightStyle = .mist { didSet { updateHighlight() } }
    override var isSelected: Bool { didSet { updateHighlight() } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        // Let the subtle celadon halo cross row edges; the scroll viewport
        // remains the clipping boundary. Candidate geometry is unchanged.
        if #available(macOS 14.0, *) { clipsToBounds = false }
        addSubview(hdr, positioned: .below, relativeTo: nil)
        hdr.onPresentationChange = { [weak self] in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func layout() { super.layout(); hdr.frame = bounds.insetBy(dx: 3, dy: 1) }
    private func updateHighlight() {
        hdr.material = style == .pearl ? .pearl : (style == .marker ? .marker : .celadon)
        hdr.active = isSelected && style != .graphite
        updateContentContrast(); needsDisplay = true
    }
    private func updateContentContrast() {
        for case let cell as CandidateCellView in subviews { cell.applySelection(style: style, selected: isSelected) }
    }
    override func didAddSubview(_ subview: NSView) { super.didAddSubview(subview); updateContentContrast() }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override func drawSelection(in dirtyRect: NSRect) {
        if style == .graphite || !hdr.hasPresentedFrame {
            SelectionPaint.draw(style, in: bounds.insetBy(dx: 3, dy: 1), dark: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        }
    }
}
