import AppKit

@main struct VignetteTests {
    static func main() {
        for (width, height) in [(640, 400), (400, 640)] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let view = VignetteView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            view.draw(view.bounds)
            NSGraphicsContext.restoreGraphicsState()
            let center = bitmap.colorAt(x: width / 2, y: height / 2)!.alphaComponent
            let edge = bitmap.colorAt(x: width / 2, y: 0)!.alphaComponent
            let corner = bitmap.colorAt(x: 0, y: 0)!.alphaComponent
            precondition(abs(center - 0.04) < 0.006, "Center must be 4%")
            precondition(abs(corner - 0.20) < 0.006, "Corner must be 20%")
            precondition(center < edge && edge < corner, "Gradient must darken outward")
        }
        print("PASS: vignette rendering in landscape and portrait (4% center, 20% corners)")
    }
}
