import AppKit

@main struct NativeUITests {
    static func main() throws {
        _ = NSApplication.shared
        let indicator = ScanMotionView(frame: NSRect(x: 22, y: 84, width: 20, height: 20))
        indicator.compact = true
        // Indexing -> searching -> idle used to place the text over a stale dot.
        for (indexing, searching) in [(true, false), (false, true), (true, true), (false, false)] {
            let busy = SearchStatusLayout.busy(indexing: indexing, searching: searching)
            indicator.configure(style: .pulse, active: busy, reduced: false)
            for width: CGFloat in [600,720,840] {
                for textHeight: CGFloat in [14,20,28] {
                    let text = SearchStatusLayout.textFrame(width: width, rowsHeight: 0, textHeight: textHeight, busy: busy)
                    precondition(abs(text.midY - indicator.frame.midY) < 0.01)
                    precondition(text.maxX == width - 22)
                    if busy { precondition(text.minX >= indicator.frame.maxX + 6 && !indicator.isHidden) }
                    else { precondition(text.minX == 22 && indicator.isHidden) }
                }
            }
        }
        print("PASS: status dot and text share busy state, spacing and vertical alignment")
        for style in ScanMotionStyle.allCases {
            var settings = Settings(); settings.scanMotion = style.rawValue
            let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
            precondition(restored.scanMotion == style.rawValue)
            for compact in [false, true] {
                let motion = ScanMotionView(frame: NSRect(x: 0, y: 0, width: compact ? 20 : 720, height: compact ? 20 : 400))
                motion.compact = compact
                motion.configure(style: style, active: true, reduced: false)
                precondition(!motion.isHidden && !(motion.layer?.sublayers?.isEmpty ?? true))
                precondition(motion.hitTest(.zero) == nil)
                motion.configure(style: style, active: true, reduced: true)
                precondition(compact ? !(motion.layer?.sublayers?.isEmpty ?? true) : (motion.layer?.sublayers?.isEmpty ?? true))
                motion.configure(style: style, active: false, reduced: false)
                precondition(motion.isHidden && (motion.layer?.sublayers?.isEmpty ?? true))
            }
        }
        for size in [NSSize(width: 600, height: 80), NSSize(width: 720, height: 422), NSSize(width: 840, height: 608)] {
            for style in [ScanMotionStyle.pulse] {
                let motion = ScanMotionView(frame: NSRect(origin: .zero, size: size))
                motion.configure(style: style, active: true, reduced: false)
                let expected = SearchSurfaceGeometry.path(in: motion.bounds)
                for case let edge as CAShapeLayer in motion.layer!.sublayers! {
                    precondition(edge.frame == motion.bounds)
                    precondition(edge.path == expected)
                    precondition(edge.shadowRadius > 0 && edge.shadowOpacity > 0)
                }
                motion.cornerRadius = 19; motion.outlineInset = 0; motion.layout()
                let preview = SearchSurfaceGeometry.path(in: motion.bounds, radius: 19, inset: 0)
                precondition((motion.layer!.sublayers!.first as! CAShapeLayer).path == preview)
            }
        }
        print("PASS: shared outline geometry across three panel sizes, preview radius and glow layers")
        let previewMotion = ScanMotionView(frame: NSRect(x: 0, y: 0, width: 440, height: 134))
        previewMotion.effectScale = 440 / 720
        previewMotion.cornerRadius = 19; previewMotion.outlineInset = 0
        for style in [ScanMotionStyle.wave, .flow] {
            previewMotion.configure(style: style, active: true, reduced: false)
            let clip = previewMotion.layer!.sublayers!.first!
            precondition((clip.mask as! CAShapeLayer).path == SearchSurfaceGeometry.path(in: previewMotion.bounds, radius: 19, inset: style == .flow ? 1.5 : 0))
            if style == .wave {
                precondition(clip.sublayers!.count == 3 && clip.sublayers!.allSatisfy { $0.frame.height > previewMotion.bounds.height },
                             "Ambient waves cover the backdrop, rather than the panel lower edge")
            } else {
                let glow = clip.sublayers!.first!
                let sweep = glow.animation(forKey: "transform.translation.x") as! CABasicAnimation
                precondition((sweep.toValue as! CGFloat) == 880)
            }
            previewMotion.configure(style: style, active: false, reduced: false)
            precondition(previewMotion.layer?.sublayers?.isEmpty ?? true)
        }
        print("PASS: miniature wave proportions, flow travel, clipping and stop")
        let orbit = ScanMotionView(frame: NSRect(x: 0, y: 0, width: 720, height: 400))
        orbit.configure(style: .orbit, active: true, reduced: false)
        let spectrum = orbit.layer!.sublayers!.first as! CAGradientLayer
        let trail = spectrum.mask as! CAShapeLayer
        precondition(trail.shadowOpacity == 0 && spectrum.colors!.count == 5)
        let movement = trail.animation(forKey: "lineDashPhase") as! CAKeyframeAnimation
        let values = movement.values as! [NSNumber]
        let steps = zip(values, values.dropFirst()).map { $0.doubleValue - $1.doubleValue }
        precondition(steps.allSatisfy { $0 > 0 })
        precondition(steps[60] > steps[0] * 5 && abs(steps.first! - steps.last!) < 0.001)
        precondition(trail.path!.boundingBoxOfPath == SearchSurfaceGeometry.path(in: orbit.bounds).boundingBoxOfPath)
        print("PASS: rainbow trail has no halo, continuous positive travel, slow seam and fast opposite point")
        precondition(ScanMotionStyle(rawValue: Settings().scanMotion ?? "") == nil)
        final class Document: NSView { override var isFlipped: Bool { true } }
        let document = Document(frame: NSRect(x: 0, y: 0, width: 680, height: 1000))
        let page = SettingsPage(document: document); page.layout(); page.scroll.tile(); page.updateHint()
        precondition(page.scroll.hasVerticalScroller && page.bottomVeil.frame.height == 40 && page.topVeil.isHidden)
        page.scroll.contentView.scroll(to: NSPoint(x: 0, y: 1000))
        page.scroll.reflectScrolledClipView(page.scroll.contentView); page.updateHint()
        precondition(page.bottomVeil.isHidden && page.topVeil.frame.height == 24)
        document.setFrameSize(NSSize(width: 680, height: 100))
        page.scroll.contentView.scroll(to: .zero); page.scroll.tile(); page.updateHint()
        precondition(!page.scroll.hasVerticalScroller && page.bottomVeil.isHidden && page.topVeil.isHidden)
        document.setFrameSize(NSSize(width: 680, height: page.bounds.height + 38))
        for remaining: CGFloat in [38, 20, 5, 0] {
            page.scroll.contentView.scroll(to: NSPoint(x: 0, y: 38 - remaining))
            page.scroll.reflectScrolledClipView(page.scroll.contentView); page.updateHint()
            precondition(abs(page.bottomVeil.frame.height - remaining) < 0.01)
            precondition(abs(page.bottomVeil.alphaValue - min(1, remaining / 12)) < 0.01)
            precondition(page.bottomVeil.hitTest(.zero) == nil)
        }
        precondition(page.scroll.frame.height == page.bounds.height)
        print("PASS: continuous 38/20/5/0-point edge extent, terminal opacity, mouse passthrough and reclaimed hint space")
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            for top in [false, true] {
                let veil = ScrollEdgeVeil(top: top)
                veil.appearance = NSAppearance(named: name)
                veil.viewDidChangeEffectiveAppearance()
                veil.update(distance: 40, maximum: 40, width: 500, edge: 100)
                let overlay = veil.subviews.last!
                precondition(overlay.isFlipped == veil.isFlipped,
                             "Tint and fade must run in the same physical direction")
                precondition(veil.subviews.first === veil.material && overlay !== veil.material)
                let tint = overlay.layer!.sublayers!.first as! CAGradientLayer
                let colors = tint.colors as! [CGColor]
                veil.effectiveAppearance.performAsCurrentDrawingAppearance {
                    let expected = name == .darkAqua ? NSColor.windowBackgroundColor : NSColor(srgbRed: 0.957, green: 0.957, blue: 0.945, alpha: 1)
                    precondition(colors[top ? 0 : 1] == expected.cgColor)
                }
                precondition(overlay.frame == veil.bounds && tint.frame == overlay.bounds)
            }
        }
        print("PASS: canvas tint above material, matching light/dark edge colors and overlay geometry")
        let directories = DirectoryListView(paths: ["/Users/example/Documents", "~/Downloads"], frame: NSRect(x: 0, y: 0, width: 534, height: 64))
        precondition(directories.paths == ["/Users/example/Documents", "~/Downloads"] && directories.preferredHeight == 64)
        directories.layout()
        precondition(directories.fields.count == 2 && directories.fields[0].frame.width == 470)
        var layoutUpdates = 0
        directories.onHeightChange = { layoutUpdates += 1 }
        directories.remove(at: 0)
        precondition(directories.paths == ["~/Downloads"] && directories.preferredHeight == 30 && layoutUpdates == 1)
        directories.append(["/Volumes/Archive"])
        precondition(directories.paths == ["~/Downloads", "/Volumes/Archive"] && layoutUpdates == 2)
        directories.remove(at: 0); directories.remove(at: 0)
        precondition(directories.paths.isEmpty && directories.preferredHeight == 30 && layoutUpdates == 4)
        print("PASS: short pages hide empty scrollers, long pages retain overflow hints, directory rows add/edit/remove and relayout")
    }
}
