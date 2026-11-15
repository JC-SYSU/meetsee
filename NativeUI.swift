import AppKit
import QuartzCore

enum ScanMotionStyle: String, CaseIterable {
    case pulse, orbit, wave, flow
    var title: String {
        switch self {
        case .pulse: return "呼吸光点"
        case .orbit: return "细环巡游"
        case .wave: return "微波律动"
        case .flow: return "流光细线"
        }
    }
}

enum SearchSurfaceGeometry {
    static let radius: CGFloat = 22
    static func path(in bounds: CGRect, radius: CGFloat = radius, inset: CGFloat = 0.25) -> CGPath {
        ContinuousCorners.path(in: bounds.insetBy(dx: inset, dy: inset), radius: radius)
    }
    static func orbitPath(in bounds: CGRect, radius: CGFloat, inset: CGFloat) -> CGPath {
        ContinuousCorners.orbit(in: bounds.insetBy(dx: inset, dy: inset), radius: radius)
    }
}

// No timers or drawing loops: Core Animation owns the repeating motion.
final class ScanMotionView: NSView {
    private(set) var style: ScanMotionStyle = .pulse
    private(set) var running = false
    private var reduced = false
    var compact = false
    var effectScale: CGFloat = 1
    var cornerRadius: CGFloat = SearchSurfaceGeometry.radius
    var outlineInset: CGFloat = 0.25
    private var epoch = CACurrentMediaTime()
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        layer?.masksToBounds = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    func configure(style: ScanMotionStyle, active: Bool, reduced: Bool) {
        guard self.style != style || running != active || self.reduced != reduced else { return }
        self.style = style; running = active; self.reduced = reduced
        epoch = CACurrentMediaTime(); rebuild()
    }
    override func layout() { super.layout(); rebuild() }
    private func cycle(_ node: CALayer, key: String, from: Any, to: Any, duration: Double, autoreverses: Bool = false, offset: Double = 0) {
        guard !reduced else { return }
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from; a.toValue = to; a.duration = duration
        a.autoreverses = autoreverses; a.repeatCount = .infinity
        a.beginTime = epoch + offset
        a.timingFunction = CAMediaTimingFunction(name: autoreverses ? .easeInEaseOut : .linear)
        node.add(a, forKey: key)
    }
    private func shape(_ path: CGPath, fill: NSColor? = nil, stroke: NSColor? = nil, width: CGFloat = 1) -> CAShapeLayer {
        let node = CAShapeLayer(); node.frame = bounds; node.path = path
        node.contentsScale = window?.backingScaleFactor ?? 2
        node.fillColor = fill?.cgColor; node.strokeColor = stroke?.cgColor; node.lineWidth = width
        layer?.addSublayer(node); return node
    }
    private func rebuild() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        layer?.sublayers?.forEach { $0.removeAllAnimations(); $0.removeFromSuperlayer() }
        isHidden = !running
        guard running, bounds.width > 0, bounds.height > 0 else { return }
        let blue = NSColor(srgbRed: 0.28, green: 0.60, blue: 0.71, alpha: 1)
        let r = bounds.insetBy(dx: compact ? 3 : outlineInset, dy: compact ? 3 : outlineInset)
        if reduced {
            if compact { _ = shape(CGPath(ellipseIn: r.insetBy(dx: 3, dy: 3), transform: nil), fill: blue) }
            return
        }
        switch style {
        case .pulse:
            if compact {
                let dot = shape(CGPath(ellipseIn: r.insetBy(dx: 3, dy: 3), transform: nil), fill: blue)
                dot.shadowColor = blue.cgColor; dot.shadowRadius = 4; dot.shadowOpacity = 0.5; dot.shadowOffset = .zero
                cycle(dot, key: "opacity", from: 0.35, to: 1, duration: 1.35, autoreverses: true)
                cycle(dot, key: "fillColor", from: blue.cgColor, to: NSColor(srgbRed: 0.92, green: 0.99, blue: 1, alpha: 1).cgColor, duration: 1.35, autoreverses: true)
            } else {
                let path = SearchSurfaceGeometry.path(in: bounds, radius: cornerRadius, inset: outlineInset)
                // The bright phase approaches white; chroma lives in the softer halo.
                for (width, blur) in [(CGFloat(3), CGFloat(10)), (CGFloat(1.3), CGFloat(2))] {
                    let edge = shape(path, stroke: blue, width: width)
                    edge.shadowColor = NSColor.systemCyan.cgColor; edge.shadowRadius = blur
                    edge.shadowOpacity = width > 2 ? 0.65 : 0.35; edge.shadowOffset = .zero
                    let bright = NSColor(srgbRed: 0.92, green: 0.99, blue: 1, alpha: 1)
                    cycle(edge, key: "strokeColor", from: blue.withAlphaComponent(0.25).cgColor, to: bright.cgColor, duration: 1.35, autoreverses: true)
                    cycle(edge, key: "opacity", from: 0.25, to: width > 2 ? 0.55 : 1, duration: 1.35, autoreverses: true)
                    cycle(edge, key: "shadowRadius", from: 2, to: blur, duration: 1.35, autoreverses: true)
                }
            }
        case .orbit:
            let path = compact ? CGPath(ellipseIn: r, transform: nil) : SearchSurfaceGeometry.orbitPath(in: bounds, radius: cornerRadius, inset: outlineInset)
            let perimeter = compact ? CGFloat.pi * r.width : ContinuousCorners.length(of: path)
            let rainbow = CAGradientLayer(); rainbow.frame = bounds
            rainbow.colors = [NSColor.systemCyan, .systemBlue, .systemPurple, .systemPink, .systemOrange].map { $0.cgColor }
            rainbow.startPoint = CGPoint(x: 0, y: 1); rainbow.endPoint = CGPoint(x: 1, y: 0)
            let edge = CAShapeLayer(); edge.frame = bounds; edge.path = path
            edge.fillColor = nil; edge.strokeColor = NSColor.white.cgColor
            edge.lineWidth = compact ? 1.8 : 2; edge.lineCap = .round
            edge.lineDashPattern = [NSNumber(value: Double(perimeter * 0.16)), NSNumber(value: Double(perimeter * 0.84))]
            rainbow.mask = edge; layer?.addSublayer(rainbow)
            // Positive velocity throughout: slow at the seam, fastest halfway around.
            let travel = CAKeyframeAnimation(keyPath: "lineDashPhase")
            travel.values = (0...120).map { i -> NSNumber in
                let t = Double(i) / 120
                return NSNumber(value: Double(perimeter) * (0.08 - t + 0.78 * sin(2 * .pi * t) / (2 * .pi)))
            }
            travel.duration = compact ? 2.4 : 5.2; travel.repeatCount = .infinity
            travel.beginTime = epoch; travel.calculationMode = .linear
            edge.add(travel, forKey: "lineDashPhase")
        case .wave:
            if compact {
                for i in 0..<4 {
                    let bar = CALayer(); bar.frame = CGRect(x: CGFloat(i) * 4 + (bounds.width - 14) / 2, y: (bounds.height - 12) / 2, width: 2, height: 12)
                    bar.cornerRadius = 1; bar.backgroundColor = blue.cgColor; layer?.addSublayer(bar)
                    cycle(bar, key: "transform.scale.y", from: 0.3, to: 1, duration: 0.65, autoreverses: true, offset: Double(i) * 0.12)
                }
            } else {
                let clip = CALayer(); clip.frame = bounds
                let mask = CAShapeLayer(); mask.frame = clip.bounds
                mask.path = SearchSurfaceGeometry.path(in: bounds, radius: cornerRadius, inset: outlineInset)
                clip.mask = mask; layer?.addSublayer(clip)
                for (i, color) in [NSColor.systemTeal, .systemIndigo, .systemPurple].enumerated() {
                    let glow = CAGradientLayer(); glow.type = .radial
                    glow.colors = [color.withAlphaComponent(0.20).cgColor, color.withAlphaComponent(0).cgColor]
                    glow.startPoint = CGPoint(x: 0.5, y: 0.5); glow.endPoint = CGPoint(x: 1, y: 1)
                    glow.frame = CGRect(x: bounds.width * (CGFloat(i) * 0.30 - 0.2), y: -bounds.height * 0.25,
                                        width: bounds.width * 0.85, height: bounds.height * 1.5)
                    clip.addSublayer(glow)
                    cycle(glow, key: "opacity", from: 0.2, to: 1, duration: 3.2, autoreverses: true, offset: Double(i) * 0.8)
                    cycle(glow, key: "transform.translation.x", from: -bounds.width * 0.12, to: bounds.width * 0.12,
                          duration: 4.4, autoreverses: true, offset: Double(i) * 0.8)
                }
            }
        case .flow:
            let clip = CALayer(); clip.frame = bounds; clip.cornerRadius = compact ? 2 : 0; clip.masksToBounds = true
            if compact { clip.frame = CGRect(x: 0, y: (bounds.height - 3) / 2, width: bounds.width, height: 3); clip.backgroundColor = blue.withAlphaComponent(0.15).cgColor }
            if !compact {
                let mask = CAShapeLayer(); mask.frame = clip.bounds
                mask.path = SearchSurfaceGeometry.path(in: bounds, radius: cornerRadius, inset: max(1.5, outlineInset))
                mask.fillColor = nil; mask.strokeColor = NSColor.white.cgColor; mask.lineWidth = 3
                clip.mask = mask
            }
            layer?.addSublayer(clip)
            let glow = CAGradientLayer(); glow.frame = CGRect(x: -bounds.width, y: 0, width: bounds.width, height: clip.bounds.height)
            let color = compact ? blue : NSColor(srgbRed: 0.86, green: 0.98, blue: 1, alpha: 1)
            glow.colors = [color.withAlphaComponent(0).cgColor, NSColor.systemCyan.cgColor, color.cgColor, NSColor.systemCyan.cgColor, color.withAlphaComponent(0).cgColor]
            glow.locations = [0, 0.40, 0.50, 0.60, 1]
            glow.startPoint = CGPoint(x: 0, y: 0.25); glow.endPoint = CGPoint(x: 1, y: 0.75)
            clip.addSublayer(glow)
            cycle(glow, key: "transform.translation.x", from: 0, to: bounds.width * 2, duration: compact ? 1.9 : 2.6)
        }
    }
}

// Settings-only controls: custom paint, native button tracking and actions.
private final class SettingsButtonCell: NSButtonCell {
    override func hitTest(for event: NSEvent, in frame: NSRect, of view: NSView) -> NSCell.HitResult {
        guard isEnabled, frame.contains(view.convert(event.locationInWindow, from: nil)) else { return [] }
        return [.contentArea, .trackableArea]
    }
}

class SettingsActionButton: NSButton {
    var prominent = false { didSet { needsDisplay = true } }
    private(set) var isHovered = false
    private var hoverTracking: NSTrackingArea?
    override var isEnabled: Bool {
        didSet { if !isEnabled { isHovered = false }; needsDisplay = true }
    }
    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        cell = SettingsButtonCell(textCell: "")
        self.title = title; self.target = target; self.action = action
        setButtonType(.momentaryPushIn); isBordered = false
        font = .systemFont(ofSize: 12); focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverTracking = area
    }
    override func mouseEntered(with event: NSEvent) { isHovered = isEnabled; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    override func drawFocusRingMask() {
        ContinuousCorners.bezier(in: bounds.insetBy(dx: 1, dy: 1), radius: 7).fill()
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let strong = prominent || state == .on
        let ink = NSColor(srgbRed: 41 / 255, green: 59 / 255, blue: 77 / 255, alpha: 1)
        let shape = ContinuousCorners.bezier(in: bounds.insetBy(dx: 1, dy: 1), radius: 7)
        let fill = strong ? ink : NSColor.white.withAlphaComponent(dark ? 0.07 : 0.60)
        fill.withAlphaComponent(isEnabled ? fill.alphaComponent : fill.alphaComponent * 0.35).setFill(); shape.fill()
        let border = dark ? NSColor.white.withAlphaComponent(0.18) : (strong ? ink : NSColor(srgbRed: 211 / 255, green: 216 / 255, blue: 220 / 255, alpha: 1))
        border.withAlphaComponent(isEnabled ? border.alphaComponent : border.alphaComponent * 0.4).setStroke()
        shape.lineWidth = 1; shape.stroke()
        if isHovered && isEnabled {
            (strong || dark ? NSColor.white : ink).withAlphaComponent(strong ? 0.12 : 0.07).setFill(); shape.fill()
        }
        if isHighlighted && isEnabled {
            (strong ? NSColor.white : NSColor.labelColor).withAlphaComponent(0.09).setFill(); shape.fill()
        }
        let textColor: NSColor = !isEnabled ? .disabledControlTextColor : (strong ? .white : (dark ? .labelColor : NSColor(srgbRed: 66 / 255, green: 75 / 255, blue: 85 / 255, alpha: 1)))
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 12), .foregroundColor: textColor, .paragraphStyle: paragraph]
        let height = (title as NSString).size(withAttributes: attrs).height
        (title as NSString).draw(in: NSRect(x: 6, y: (bounds.height - height) / 2, width: max(0, bounds.width - 12), height: height), withAttributes: attrs)
    }
}

final class SettingsCheckbox: SettingsActionButton {
    override init(title: String, target: AnyObject?, action: Selector?) {
        super.init(title: title, target: target, action: action)
        setButtonType(.switch)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(title)
        font = .systemFont(ofSize: 13)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func accessibilityValue() -> Any? { NSNumber(value: state.rawValue) }
    private var boxRect: NSRect { NSRect(x: 3, y: (bounds.height - 16) / 2, width: 16, height: 16) }
    override func drawFocusRingMask() {
        ContinuousCorners.bezier(in: boxRect, radius: 4).fill()
    }
    override var focusRingMaskBounds: NSRect { boxRect }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let checked = state != .off
        let ink = NSColor(srgbRed: 41 / 255, green: 59 / 255, blue: 77 / 255, alpha: 1)
        let box = boxRect
        let shape = ContinuousCorners.bezier(in: box, radius: 4)
        if isHovered && isEnabled {
            (dark ? NSColor.white : ink).withAlphaComponent(0.10).setFill()
            ContinuousCorners.bezier(in: box.insetBy(dx: -3, dy: -3), radius: 7).fill()
        }
        let fill = checked ? ink : NSColor.white.withAlphaComponent(dark ? 0.07 : 0.6)
        fill.withAlphaComponent(isEnabled ? fill.alphaComponent : fill.alphaComponent * 0.35).setFill(); shape.fill()
        let border = dark ? NSColor.white.withAlphaComponent(0.35) : (checked ? ink : NSColor(srgbRed: 0.64, green: 0.68, blue: 0.71, alpha: 1))
        border.withAlphaComponent(isEnabled ? border.alphaComponent : border.alphaComponent * 0.4).setStroke()
        shape.lineWidth = 1; shape.stroke()
        if (isHovered || isHighlighted) && isEnabled {
            (checked || dark ? NSColor.white : ink).withAlphaComponent(isHighlighted ? 0.19 : 0.09).setFill(); shape.fill()
        }
        if checked {
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: box.minX + x, y: box.minY + (isFlipped ? y : 16 - y))
            }
            let mark = NSBezierPath(); mark.lineWidth = 1.8; mark.lineCapStyle = .round; mark.lineJoinStyle = .round
            if state == .mixed { mark.move(to: point(4, 8)); mark.line(to: point(12, 8)) }
            else { mark.move(to: point(3.5, 8)); mark.line(to: point(7, 11)); mark.line(to: point(12.5, 5)) }
            NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.5).setStroke(); mark.stroke()
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor, .paragraphStyle: paragraph]
        let height = (title as NSString).size(withAttributes: attrs).height
        (title as NSString).draw(in: NSRect(x: 27, y: (bounds.height - height) / 2, width: max(0, bounds.width - 29), height: height), withAttributes: attrs)
    }
}

private final class SettingsSegmentButton: SettingsActionButton {
    override func keyDown(with event: NSEvent) {
        if let group = superview as? SettingsSegmentedControl, [123, 124, 125, 126].contains(event.keyCode) {
            group.moveSelection(from: tag, step: [123, 126].contains(event.keyCode) ? -1 : 1)
        } else { super.keyDown(with: event) }
    }
}

final class SettingsSegmentedControl: NSControl {
    private(set) var buttons: [SettingsActionButton] = []
    var selectedSegment = -1 {
        didSet {
            for (index, button) in buttons.enumerated() {
                button.state = index == selectedSegment ? .on : .off; button.needsDisplay = true
            }
        }
    }
    override var isEnabled: Bool { didSet { buttons.forEach { $0.isEnabled = isEnabled; $0.needsDisplay = true } } }
    init(labels: [String], selected: Int, frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityRole(.group)
        for (index, title) in labels.enumerated() {
            let button = SettingsSegmentButton(title: title, target: self, action: #selector(selectOption(_:)))
            button.setButtonType(.radio); button.tag = index
            buttons.append(button); addSubview(button)
        }
        selectedSegment = selected
        for (index, button) in buttons.enumerated() { button.state = index == selected ? .on : .off }
        layout()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    func setLabel(_ label: String, forSegment index: Int) {
        guard buttons.indices.contains(index) else { return }
        buttons[index].title = label
        buttons[index].needsDisplay = true
    }
    override func layout() {
        super.layout()
        guard !buttons.isEmpty else { return }
        let gap: CGFloat = 4
        let width = max(0, (bounds.width - gap * CGFloat(buttons.count - 1)) / CGFloat(buttons.count))
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: bounds.height)
        }
    }
    @objc private func selectOption(_ sender: NSButton) {
        guard isEnabled else { return }
        selectedSegment = sender.tag
        sendAction(action, to: target)
    }
    func moveSelection(from index: Int, step: Int) {
        guard isEnabled, !buttons.isEmpty else { return }
        let next = (index + step + buttons.count) % buttons.count
        window?.makeFirstResponder(buttons[next])
        buttons[next].performClick(nil)
    }
}

final class DirectoryListView: NSView {
    override var isFlipped: Bool { true }
    private(set) var fields: [NSTextField] = []
    var onHeightChange: (() -> Void)?
    private let rowHeight: CGFloat = 30
    private let rowGap: CGFloat = 4

    var paths: [String] { fields.map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) } }
    var preferredHeight: CGFloat { max(rowHeight, CGFloat(max(fields.count, 1)) * (rowHeight + rowGap) - rowGap) }

    init(paths: [String], frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        reload(paths)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    func append(_ paths: [String]) {
        reload(self.paths + paths.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        onHeightChange?()
    }

    func remove(at index: Int) {
        guard fields.indices.contains(index) else { return }
        var next = self.paths
        next.remove(at: index)
        reload(next)
        onHeightChange?()
    }

    private func reload(_ paths: [String]) {
        subviews.forEach { $0.removeFromSuperview() }
        fields.removeAll()
        for (index, path) in paths.enumerated() {
            let field = NSTextField(frame: .zero)
            field.stringValue = path
            field.placeholderString = "绝对路径或 ~/ 路径"
            field.isBezeled = true
            field.bezelStyle = .roundedBezel
            field.font = .systemFont(ofSize: 12)
            field.lineBreakMode = .byTruncatingMiddle
            field.usesSingleLineMode = true
            field.toolTip = path.isEmpty ? nil : path
            field.setAccessibilityLabel("搜索目录")
            addSubview(field)
            fields.append(field)

            let remove = SettingsActionButton(title: "移除", target: self, action: #selector(removeRow(_:)))
            remove.tag = index
            remove.bezelStyle = .texturedRounded
            remove.font = .systemFont(ofSize: 11)
            remove.setAccessibilityLabel("移除搜索目录")
            addSubview(remove)
        }
        if paths.isEmpty {
            let empty = NSTextField(labelWithString: "尚未添加目录")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            empty.setAccessibilityLabel("尚未添加目录")
            addSubview(empty)
        }
        needsLayout = true
    }

    @objc private func removeRow(_ sender: NSButton) { remove(at: sender.tag) }

    override func layout() {
        super.layout()
        let buttonWidth: CGFloat = 56
        let fieldWidth = max(0, bounds.width - buttonWidth - 8)
        for (index, field) in fields.enumerated() {
            let y = CGFloat(index) * (rowHeight + rowGap)
            field.frame = NSRect(x: 0, y: y, width: fieldWidth, height: rowHeight)
            if let remove = subviews.compactMap({ $0 as? NSButton }).first(where: { $0.tag == index }) {
                remove.frame = NSRect(x: fieldWidth + 8, y: y + 1, width: buttonWidth, height: rowHeight - 2)
            }
        }
        if fields.isEmpty, let empty = subviews.compactMap({ $0 as? NSTextField }).first {
            empty.frame = NSRect(x: 4, y: 5, width: bounds.width - 8, height: rowHeight - 2)
        }
    }
}

/// Public AppKit material plus a gradient mask, not a private variable-blur filter.
final class ScrollEdgeVeil: NSView {
    private final class TintOverlay: NSView {
        override var isFlipped: Bool { true }
    }
    let material = NSVisualEffectView()
    private let fade = CAGradientLayer()
    private let tint = CAGradientLayer()
    private let tintOverlay = TintOverlay()
    let top: Bool
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    init(top: Bool) {
        self.top = top
        super.init(frame: .zero)
        wantsLayer = true
        material.material = .windowBackground
        material.blendingMode = .withinWindow
        material.state = .active
        material.autoresizingMask = [.width, .height]
        addSubview(material)
        // Match the veil's top-down coordinates: an unflipped overlay reverses
        // the tint, exposing the pale material precisely at the opaque edge.
        // Keep the canvas tint above AppKit's material backing layers.
        tintOverlay.wantsLayer = true
        addSubview(tintOverlay, positioned: .above, relativeTo: material)
        tintOverlay.layer?.addSublayer(tint)
        fade.startPoint = CGPoint(x: 0.5, y: 0)
        fade.endPoint = CGPoint(x: 0.5, y: 1)
        tint.startPoint = fade.startPoint; tint.endPoint = fade.endPoint
        let alphas: [CGFloat] = top ? [1, 0.65, 0] : [0, 0.65, 1]
        fade.colors = alphas.map { NSColor.black.withAlphaComponent($0).cgColor }
        fade.locations = top ? [0, 0.45, 1] : [0, 0.55, 1]
        layer?.mask = fade
        setAccessibilityElement(false)
        updateTint()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateTint() }
    private func updateTint() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = dark ? NSColor.windowBackgroundColor : NSColor(srgbRed: 0.957, green: 0.957, blue: 0.945, alpha: 1)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            tint.colors = (top ? [CGFloat(1), 0] : [CGFloat(0), 1]).map { color.withAlphaComponent($0).cgColor }
        }
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        material.frame = bounds; tintOverlay.frame = bounds
        fade.frame = bounds; tint.frame = tintOverlay.bounds
        CATransaction.commit()
    }
    func update(distance: CGFloat, maximum: CGFloat, width: CGFloat, edge: CGFloat) {
        let extent = min(maximum, max(0, distance))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        frame = NSRect(x: 0, y: top ? edge : edge - extent, width: width, height: extent)
        // Fade the last few points instead of leaving a dense, thin line.
        alphaValue = min(1, extent / 12)
        isHidden = extent <= 0
        layoutSubtreeIfNeeded()
        CATransaction.commit()
    }
}

final class SettingsPage: NSView {
    override var isFlipped: Bool { true }
    let scroll = NSScrollView()
    let topVeil = ScrollEdgeVeil(top: true)
    let bottomVeil = ScrollEdgeVeil(top: false)
    private var observations: [NSObjectProtocol] = []
    init(document: NSView) {
        super.init(frame: NSRect(x: 0, y: 0, width: 712, height: 570))
        scroll.hasVerticalScroller = false; scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay; scroll.drawsBackground = false
        scroll.documentView = document; addSubview(scroll)
        addSubview(topVeil); addSubview(bottomVeil)
        scroll.contentView.postsBoundsChangedNotifications = true; document.postsFrameChangedNotifications = true
        for (name, object) in [(NSView.boundsDidChangeNotification, scroll.contentView as NSView), (NSView.frameDidChangeNotification, document)] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in self?.updateHint() })
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    deinit { observations.forEach(NotificationCenter.default.removeObserver) }
    override func layout() {
        super.layout()
        scroll.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height))
        updateHint()
    }
    func updateHint() {
        let height = scroll.documentView?.bounds.height ?? 0
        let viewport = scroll.contentView.bounds.height
        let shouldScroll = height > viewport + 1
        if scroll.hasVerticalScroller != shouldScroll {
            scroll.hasVerticalScroller = shouldScroll
            scroll.tile()
        }
        let visible = scroll.documentVisibleRect
        let overflow = max(0, height - viewport)
        let offset = min(overflow, max(0, visible.minY))
        // Leave the native overlay scroller unobscured.
        let width = max(0, scroll.contentView.bounds.width - (scroll.hasVerticalScroller ? 14 : 0))
        topVeil.update(distance: offset, maximum: 24, width: width, edge: 0)
        bottomVeil.update(distance: overflow - offset, maximum: 40, width: width, edge: bounds.height)
    }
}

enum SettingsNavigation {
    static let items: [(id: String, title: String, y: CGFloat)] = [
        ("general", "通用", 112),
        ("scope", "搜索范围", 174),
        ("search", "搜索行为", 220),
        ("pins", "常用置顶", 266),
        ("diagnostics", "检索诊断", 312),
        ("interaction", "交互", 374),
        ("appearance", "外观", 420)
    ]
}

final class SettingsSidebarButton: SettingsActionButton {
    override func drawFocusRingMask() {
        ContinuousCorners.bezier(in: bounds.insetBy(dx: 1, dy: 1), radius: 10).fill()
    }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let selected = state == .on
        let shape = ContinuousCorners.bezier(in: bounds.insetBy(dx: 1, dy: 1), radius: 10)
        if selected {
            (dark ? NSColor(srgbRed: 0.23, green: 0.28, blue: 0.25, alpha: 1)
                  : NSColor(srgbRed: 0.88, green: 0.91, blue: 0.87, alpha: 0.85)).setFill()
            shape.fill()
        }
        if (isHovered || isHighlighted) && isEnabled {
            (dark ? NSColor.white : NSColor(srgbRed: 0.32, green: 0.40, blue: 0.34, alpha: 1))
                .withAlphaComponent(isHighlighted ? 0.14 : 0.07).setFill()
            shape.fill()
        }
        if selected {
            (dark ? NSColor(srgbRed: 0.67, green: 0.77, blue: 0.68, alpha: 1)
                  : NSColor(srgbRed: 0.29, green: 0.38, blue: 0.31, alpha: 1)).setFill()
            NSBezierPath(roundedRect: NSRect(x: 8, y: bounds.midY - 8, width: 3, height: 16), xRadius: 1.5, yRadius: 1.5).fill()
        }
        let textFont = font ?? NSFont.systemFont(ofSize: 13)
        let textColor: NSColor = !isEnabled ? .disabledControlTextColor : (dark ? .labelColor : NSColor(srgbRed: 0.20, green: 0.25, blue: 0.22, alpha: 1))
        let size = (title as NSString).size(withAttributes: [.font: textFont])
        (title as NSString).draw(at: NSPoint(x: 24, y: (bounds.height - size.height) / 2), withAttributes: [.font: textFont, .foregroundColor: textColor])
    }
}

// Stable result indices, never viewport-relative indices.
enum CandidateNumberShortcut {
    static func digit(characters: String?, modifiers: NSEvent.ModifierFlags) -> Int? {
        guard modifiers.intersection([.command, .shift, .option, .control]) == .command,
              let characters, characters.count == 1, let number = Int(characters), (1...8).contains(number) else { return nil }
        return number
    }
    static func row(number: Int, visibleRows: Int, resultCount: Int, searching: Bool, markedText: Bool, repeating: Bool) -> Int? {
        guard !searching, !markedText, !repeating, number >= 1,
              number <= min(8, min(visibleRows, resultCount)) else { return nil }
        return number - 1
    }
}

final class CandidateShortcutBadge: NSView {
    var onBlue = false { didSet { needsDisplay = true } }
    var number = 1 { didSet { needsDisplay = true } }
    var restingLabel: String? { didSet { needsDisplay = true } }
    var showNumber = true { didSet { needsDisplay = true } }
    var available = true { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (onBlue ? NSColor.white.withAlphaComponent(0.16) : NSColor.labelColor.withAlphaComponent(dark ? 0.08 : 0.045)).setFill()
        ContinuousCorners.bezier(in: bounds.insetBy(dx: 0.5, dy: 0.5), radius: 6).fill()
        let text = (showNumber ? "⌘\(number)" : (restingLabel ?? "")) as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: onBlue ? NSColor.white.withAlphaComponent(available ? 1 : 0.5) : (available ? NSColor.secondaryLabelColor : NSColor.disabledControlTextColor)]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
}

/// Align the two-line typographic block, not the text-field frames. The same
/// translation is applied to both fields, preserving their existing line gap.
enum CandidateTextLayout {
    static func typographicBounds(_ field: NSTextField) -> ClosedRange<CGFloat> {
        let font = field.font ?? NSFont.systemFont(ofSize: 13)
        let baseline = field.frame.minY + field.firstBaselineOffsetFromTop
        return (baseline - font.ascender)...(baseline - font.descender)
    }
    static func center(name: NSTextField, path: NSTextField, in bounds: NSRect) {
        let titleBounds = typographicBounds(name)
        let pathBounds = typographicBounds(path)
        let top = min(titleBounds.lowerBound, pathBounds.lowerBound)
        let bottom = max(titleBounds.upperBound, pathBounds.upperBound)
        let offset = bounds.midY - (top + bottom) / 2
        name.frame.origin.y += offset
        path.frame.origin.y += offset
    }
    static func titleCenter(_ field: NSTextField) -> CGFloat {
        let range = typographicBounds(field)
        return (range.lowerBound + range.upperBound) / 2
    }
}

/// A status plaque, not an action: fixed typography matches the approved preview.
final class PinnedStatusBadge: NSView {
    var onBlue = false { didSet { needsDisplay = true } }
    static let size = NSSize(width: 25, height: 13)
    static let gap: CGFloat = 7
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "常用置顶"
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("常用置顶")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    static func place(after title: NSTextField) -> NSRect {
        // Reserve the plaque before truncation, so long names never collide with it.
        title.frame.size.width = max(0, title.frame.width - size.width - gap)
        let textRect = title.cell?.titleRect(forBounds: title.bounds) ?? title.bounds
        let textWidth = min(title.attributedStringValue.size().width, textRect.width)
        let x = title.frame.minX + textRect.minX + textWidth + gap
        return NSRect(x: x, y: CandidateTextLayout.titleCenter(title) - size.height / 2,
                      width: size.width, height: size.height)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = dark ? NSColor(srgbRed: 68/255, green: 100/255, blue: 127/255, alpha: 1)
            : NSColor(srgbRed: 62/255, green: 88/255, blue: 112/255, alpha: 1)
        (onBlue ? NSColor.white.withAlphaComponent(0.20) : color).setFill()
        ContinuousCorners.bezier(in: bounds, radius: 2.5).fill()
        let text = "置顶" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8, weight: .medium), .foregroundColor: NSColor.white]
        let textSize = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - textSize.width)/2, y: (bounds.height - textSize.height)/2), withAttributes: attrs)
    }
}

// One busy-state rule for both status text spacing and the activity indicator.
enum SearchStatusLayout {
    static func busy(indexing: Bool, searching: Bool) -> Bool { indexing || searching }
    static func textFrame(width: CGFloat, rowsHeight: CGFloat, textHeight: CGFloat, busy: Bool) -> NSRect {
        let x: CGFloat = busy ? 48 : 22
        return NSRect(x: x, y: 84 + rowsHeight + (20 - textHeight) / 2,
                      width: width - x - 22, height: textHeight)
    }
}
