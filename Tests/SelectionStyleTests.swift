import AppKit

@main struct SelectionStyleTests {
    static func main() {
        _ = NSApplication.shared
        let hitWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        for style in HighlightStyle.allCases {
            let button = ThemeChoiceButton(style: style, frame: NSRect(x: 0, y: 0, width: 144, height: 36))
            hitWindow.contentView!.addSubview(button)
            button.setFrameOrigin(NSPoint(x: 20, y: 20))
            func hit(_ point: NSPoint) -> NSCell.HitResult {
                let event = NSEvent.mouseEvent(with: .leftMouseDown, location: button.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: hitWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                return button.cell!.hitTest(for: event, in: button.bounds, of: button)
            }
            for state in [NSControl.StateValue.off, .on] {
                button.state = state
                for x: CGFloat in [1, 6, 23, 54, 94, 122, 138, 143] {
                    for y: CGFloat in [1, 18, 35] {
                        precondition(hit(NSPoint(x: x, y: y)).contains(.trackableArea), "Entire theme button must track clicks")
                    }
                }
            }
            for point in [NSPoint(x: -1, y: 18), NSPoint(x: 145, y: 18), NSPoint(x: 72, y: -1), NSPoint(x: 72, y: 37)] {
                precondition(hit(point).isEmpty, "Outside button must not track clicks")
            }
            button.isEnabled = false
            precondition(hit(NSPoint(x: 72, y: 18)).isEmpty)
            button.isEnabled = true
            precondition(button.title.count == 2 && button.toolTip == style.detail)
            precondition(button.acceptsFirstResponder && button.style == style)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                button.appearance = NSAppearance(named: appearance)
                for state in [NSControl.StateValue.off, .on] {
                    button.state = state
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 144, pixelsHigh: 36, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                    button.effectiveAppearance.performAsCurrentDrawingAppearance { button.draw(button.bounds) }
                    NSGraphicsContext.restoreGraphicsState()
                    precondition(bitmap.colorAt(x: 23, y: 18)!.alphaComponent > 0.9)
                    let fill = bitmap.colorAt(x: 100, y: 18)!.usingColorSpace(.sRGB)!
                    if state == .on {
                        precondition(abs(fill.redComponent - 41 / 255) < 0.02)
                        precondition(abs(fill.greenComponent - 59 / 255) < 0.02)
                        precondition(abs(fill.blueComponent - 77 / 255) < 0.02)
                        precondition(fill.alphaComponent > 0.99)
                    } else {
                        precondition(abs(fill.alphaComponent - (appearance == .aqua ? 0.60 : 0.07)) < 0.02)
                    }
                }
            }
        }
        print("PASS: compact theme buttons, tooltips, focus eligibility and light/dark on/off swatches")
        print("PASS: all theme buttons track their full surface in both states; outside and disabled regions are excluded")
        let preview = StylePreview(frame: NSRect(x: 0, y: 0, width: 480, height: 170))
        let content = preview.subviews.last!
        let motion = NSView(frame: .zero)
        preview.insertMotion(motion)
        let motionIndex = preview.subviews.firstIndex(of: motion)!
        let contentIndex = preview.subviews.firstIndex(of: content)!
        precondition(motionIndex < contentIndex, "Motion must sit below preview text and icons")
        precondition(motion.frame == preview.bounds.insetBy(dx: 20, dy: 18))
        if #available(macOS 26.0, *), let glass = preview.subviews.compactMap({ $0 as? NSGlassEffectView }).first {
            precondition(preview.subviews.firstIndex(of: glass)! < motionIndex, "Native glass must remain below motion")
            preview.glassTintStrength = 0.5
            precondition(abs((glass.tintColor?.alphaComponent ?? -1) - 0.5) < 0.001, "Preview must use native glass tint")
            preview.glassTintStrength = 0
            precondition(glass.tintColor == nil, "Zero tint resets to system-default glass")
        }
        print("PASS: preview layering and surface alignment")
        for opacity: CGFloat in [0, 0.5, 1] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: 100, height: 80).fill(using: .copy)
            let overlay = WhiteOverlayView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
            overlay.opacity = opacity; overlay.draw(overlay.bounds)
            NSGraphicsContext.restoreGraphicsState()
            precondition(abs(bitmap.colorAt(x: 50, y: 40)!.alphaComponent - opacity) < 0.01)
            precondition(overlay.hitTest(NSPoint(x: 50, y: 40)) == nil)
        }
        print("PASS: native white overlay opacity and mouse passthrough")
        for screen in [NSRect(x: 0, y: 0, width: 1440, height: 900), NSRect(x: -1920, y: 0, width: 1920, height: 1080)] {
            for visible in [screen, NSRect(x: screen.minX + 80, y: 0, width: screen.width - 80, height: screen.height - 25), NSRect(x: screen.minX, y: 0, width: screen.width - 80, height: screen.height - 25)] {
                for width: CGFloat in [600, 720, 840] {
                    let origin = searchPanelOrigin(screen: screen, visible: visible, margin: 80, width: width)
                    precondition(abs(origin.x + 80 + width / 2 - screen.midX) < 0.001, "Glass centered at every width despite side Dock")
                }
            }
        }
        print("PASS: horizontal centering on primary/secondary displays with left/right Dock")
        for dark in [false, true] {
            var samples: [String] = []
            for style in HighlightStyle.allCases {
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 80,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                (dark ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.96, alpha: 1)).setFill()
                NSRect(x: 0, y: 0, width: 320, height: 80).fill()
                SelectionPaint.draw(style, in: NSRect(x: 10, y: 10, width: 300, height: 60), dark: dark)
                NSGraphicsContext.restoreGraphicsState()
                let center = bitmap.colorAt(x: 160, y: 40)!
                precondition(center.alphaComponent > 0.99)
                samples.append(String(format: "%.3f %.3f %.3f", Double(center.redComponent), Double(center.greenComponent), Double(center.blueComponent)))
                if style == .marker {
                    let marker = bitmap.colorAt(x: 12, y: 40)!
                    precondition(marker.blueComponent > marker.redComponent + 0.2, "Marker must be blue")
                }
                if style == .graphite {
                    let solid = center.usingColorSpace(.sRGB)!
                    let backdrop: CGFloat = dark ? 0.15 : 0.96
                    precondition(abs(solid.redComponent - (41 / 255 * 0.50 + backdrop * 0.50)) < 0.03)
                    precondition(abs(solid.greenComponent - (43 / 255 * 0.50 + backdrop * 0.50)) < 0.03)
                    precondition(abs(solid.blueComponent - (46 / 255 * 0.50 + backdrop * 0.50)) < 0.03)
                }
            }
            precondition(Set(samples).count == HighlightStyle.allCases.count, "All styles must render distinctly")
        }
        print("PASS: all selection styles rendered in light and dark palettes")
        let porcelain = PorcelainSurface(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        precondition(porcelain.hitTest(NSPoint(x: 50, y: 40)) == nil)
        let porcelainBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: porcelainBitmap)
        porcelain.draw(porcelain.bounds)
        NSGraphicsContext.restoreGraphicsState()
        let porcelainCenter = porcelainBitmap.colorAt(x: 50, y: 40)!.usingColorSpace(.sRGB)!
        precondition(porcelainCenter.alphaComponent > 0.99, "Porcelain panel is opaque")
        precondition(porcelainCenter.redComponent > 0.90 && porcelainCenter.blueComponent < porcelainCenter.redComponent, "Porcelain uses warm ivory icon colors")
        preview.style = .porcelain
        precondition(preview.subviews.compactMap { $0 as? PorcelainSurface }.first?.isHidden == false)
        precondition(PorcelainTheme.lite, "Porcelain lite stays the default until the well renderer is approved")
        precondition(preview.subviews.compactMap { $0 as? PorcelainSurface }.first?.alphaValue == 1,
            "Lite porcelain panel must be opaque")
        precondition(preview.subviews.compactMap { $0 as? PorcelainSurface }.first?.flat == true,
            "Lite porcelain panel must use the flat palette")
        preview.style = .mist
        precondition(preview.subviews.compactMap { $0 as? PorcelainSurface }.first?.isHidden == true)
        print("PASS: opaque porcelain surface, passthrough, and isolated preview switching")
        precondition(abs(SelectionPaint.inverseSubtitleColor.alphaComponent - 0.72) < 0.001)
        precondition(HighlightStyle(rawValue: "mist") == .mist, "Existing theme preferences must survive rename")
        precondition(HighlightStyle.mist.title.contains("天青"))
        precondition(CeladonMaterial.lightStrength == 1.6)
        for dark in [false, true] {
            let first = CeladonMaterial.image(dark: dark)
            precondition(first === CeladonMaterial.image(dark: dark), "Repeated paints must reuse cached material")
            let rep = first.representations.first as! NSBitmapImageRep
            precondition(rep.pixelsWide == 256 && rep.pixelsHigh == 64)
            let center = rep.colorAt(x: 128, y: 32)!.usingColorSpace(.sRGB)!
            precondition(center.greenComponent > center.redComponent + 0.04, "Restrained blue-green tint must remain visible")
            precondition(center.blueComponent >= center.greenComponent, "Restore the approved blue-light spectrum")
            precondition(abs(Double(center.alphaComponent) - CeladonMaterial.opacity(dark: dark)) < 0.005)
            // A broad light field need not differ at one arbitrary pair of
            // pixels. Sample its extent, including the soft side illumination.
            let samples = [0,64,128,192,255].flatMap { x in
                [0,16,32,48,63].map { y in rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)! }
            }
            let reds = samples.map(\.redComponent), greens = samples.map(\.greenComponent), blues = samples.map(\.blueComponent)
            let variation = max(reds.max()! - reds.min()!, greens.max()! - greens.min()!, blues.max()! - blues.min()!)
            precondition(variation > 0.005, "Light field must not collapse to flat fill")
            if dark {
                let composite = center.greenComponent * center.alphaComponent + 0.23 * (1 - center.alphaComponent)
                precondition(composite < 0.5, "Dark material must retain light-text contrast")
            }
            let boosted = CeladonMaterial.image(dark: dark, sdrBoost: true)
            precondition(boosted !== first, "SDR palette must use its own cached image")
            precondition(boosted === CeladonMaterial.image(dark: dark, sdrBoost: true), "Repeated SDR paints must reuse cached material")
            let boostedCenter = (boosted.representations.first as! NSBitmapImageRep).colorAt(x: 128, y: 32)!.usingColorSpace(.sRGB)!
            let luminance = { (c: NSColor) in 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent }
            precondition(luminance(boostedCenter) > luminance(center), "SDR palette must be brighter")
            precondition(boostedCenter.greenComponent - boostedCenter.redComponent > center.greenComponent - center.redComponent,
                "SDR palette must be more saturated")
        }
        precondition(CeladonMaterial.sdrBoost(for: nil) == false, "Missing screen must keep the published palette")
        // Real drawing, not just texture alpha: two backdrops must remain visibly
        // different through the selected surface, unlike the old 96%-opaque patch.
        func painted(_ white: CGFloat) -> NSColor {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 70,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor(white: white, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 120, height: 70).fill()
            SelectionPaint.draw(.mist, in: NSRect(x: 5, y: 5, width: 110, height: 60), dark: false)
            NSGraphicsContext.restoreGraphicsState()
            return rep.colorAt(x: 60, y: 35)!.usingColorSpace(.sRGB)!
        }
        let bright = painted(0.95), dim = painted(0.35)
        precondition(bright.redComponent - dim.redComponent > 0.28, "Lighter glaze must expose more backdrop contrast")
        precondition(bright.redComponent > 0.65 && bright.redComponent < 0.80)
        precondition(bright.greenComponent > 0.75 && bright.blueComponent > 0.75)
        precondition(abs(bright.blueComponent - bright.greenComponent) < 0.06, "Porcelain palette should remain subtly blue-green, not electric blue")
        print("PASS: celadon rename compatibility, 160% light, bounded reusable textures and light/dark material fields")
        testPorcelainMaterial()

    }
    static func testPorcelainMaterial() {
        func rep(_ kind: PorcelainMaterial.Kind, _ width: CGFloat = 720, _ height: CGFloat = 60, _ scale: CGFloat = 2) -> NSBitmapImageRep {
            PorcelainMaterial.image(kind, size: NSSize(width: width, height: height), radius: kind == .body ? 22 : 13, scale: scale).representations.first as! NSBitmapImageRep
        }
        // Read tagged sRGB bytes, not colorAt's device-colour conversion.
        func rgb(_ image: NSBitmapImageRep, _ x: Int, _ y: Int) -> [Double] {
            let offset = y * image.bytesPerRow + x * 4
            return (0..<3).map { Double(image.bitmapData![offset + $0]) / 255 }
        }
        func luminance(_ rgb: [Double]) -> Double {
            let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let body = rep(.body, 720, 320)
        let green = rep(.green)
        precondition(body.colorSpace == .sRGB && green.colorSpace == .sRGB)
        precondition(body.pixelsWide == 1440 && body.pixelsHigh == 640)
        precondition(green.pixelsWide == 1440 && green.pixelsHigh == 120)
        for (image, target) in [(body, PorcelainMaterial.bodySRGB), (green, PorcelainMaterial.greenSRGB)] {
            let center = rgb(image, image.pixelsWide / 2, image.pixelsHigh / 2)
            for c in 0..<3 { precondition(abs(center[c] * 255 - target[c]) <= 3, "Lit midpoint must retain the ICC-corrected icon sample") }
            precondition(image.bitmapData![3] == 0, "Rounded corner outside the surface must be clear")
            let offset = (image.pixelsHigh / 2) * image.bytesPerRow + (image.pixelsWide / 2) * 4
            precondition(image.bitmapData![offset + 3] == 255, "Clay substrate must be opaque")
            let top = (1..<12).map { luminance(rgb(image, image.pixelsWide / 2, $0)) }.max()!
            let bottom = (1..<12).map { luminance(rgb(image, image.pixelsWide / 2, image.pixelsHigh - 1 - $0)) }.max()!
            precondition(top > bottom + 0.08, "Upper-left light must turn across the bevel, not form a uniform outline")
        }
        var minimumContrast = Double.infinity
        let subtitle = PorcelainMaterial.subtitleColor.usingColorSpace(.sRGB)!
        let textLuma = luminance([Double(subtitle.redComponent),Double(subtitle.greenComponent),Double(subtitle.blueComponent)])
        var shades: [Double] = []
        for x in stride(from: 40, through: 1400, by: 40) {
            for y in stride(from: 14, through: 106, by: 4) {
                let c = rgb(green, x, y)
                precondition(c[1] > c[0] + 0.04 && c[1] > c[2] + 0.04, "Glaze must stay in the icon's yellow-green family")
                let luma = luminance(c)
                minimumContrast = min(minimumContrast, (luma + 0.05) / (textLuma + 0.05))
                shades.append(luma)
            }
        }
        precondition(minimumContrast >= 4.5, "Small porcelain subtitles need 4.5:1 contrast across their drawing region")
        precondition(shades.max()! - shades.min()! > 0.05, "Glaze depth and broad reflection must not collapse into a flat fill")
        let one = rep(.green, 720, 60, 1)
        for x in [30, 200, 360, 600] {
            for y in [8, 20, 30, 50] {
                let a = rgb(one,x,y), b = rgb(green,x*2,y*2)
                for c in 0..<3 { precondition(abs(a[c]-b[c]) < 0.015, "Retina must preserve the material, not stretch a small bitmap") }
            }
        }
        let narrow = rep(.green, 300, 38)
        precondition(narrow.pixelsWide == 600 && narrow.pixelsHigh == 76)
        let size = NSSize(width:720,height:60)
        let first = PorcelainMaterial.image(.green,size:size,radius:13,scale:2)
        precondition(first === PorcelainMaterial.image(.green,size:size,radius:13,scale:2), "Selection movement must reuse the rendered surface")
        let cell = CandidateCellView(frame: .zero)
        cell.textField = NSTextField(labelWithString: "title")
        cell.subtitleField = NSTextField(labelWithString: "sample")
        cell.applySelection(style: .porcelain, selected: true)
        precondition(cell.textField?.textColor == (PorcelainTheme.lite ? PorcelainLitePalette.ink : .labelColor))
        precondition(cell.subtitleField?.textColor == (PorcelainTheme.lite ? PorcelainLitePalette.ink.withAlphaComponent(0.75) : PorcelainMaterial.subtitleColor),
            "Porcelain subtitle must follow the active lite/full treatment")
        cell.applySelection(style: .mist, selected: false)
        precondition(cell.subtitleField?.textColor == .secondaryLabelColor, "Switching away must restore native text colour")
        print(String(format: "PASS: porcelain sRGB anchors, curved specular rim, opaque clay, glaze variation, Retina, cache; minimum sampled subtitle contrast %.2f:1", minimumContrast))
    }

}
