import AppKit
import Metal
import QuartzCore

@main struct HDRSelectionTests {
    static func main() throws {
        _ = NSApplication.shared
        precondition(HDRSelectionRenderer.usableHeadroom(1) == 1)
        precondition(HDRSelectionRenderer.usableHeadroom(4) == 1.6)
        precondition(HDRSelectionRenderer.usableHeadroom(.nan) == 1)
        precondition(HDRSelectionRenderer.usableHeadroom(4, material: .pearl) == 1.3)
        precondition(HDRSelectionRenderer.usableHeadroom(4, material: .marker) == 1.3)
        guard let renderer = HDRSelectionRenderer.shared else { fatalError("Metal shader failed to initialize") }
        func pixel(headroom: Float, x: Int, y: Int, material: HDRSelectionMaterial = .celadon, dark: Float = 0) throws -> [Float] {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 256, height: 64, mipmapped: false)
            desc.usage = [.renderTarget]; desc.storageMode = .shared
            let texture = renderer.device.makeTexture(descriptor: desc)!
            let buffer = renderer.queue.makeCommandBuffer()!
            renderer.encode(texture: texture, parameters: .init(size: SIMD2(256,64),headroom: headroom,dark:dark,material:material.rawValue),buffer:buffer)
            buffer.commit(); buffer.waitUntilCompleted()
            precondition(buffer.status == .completed, "GPU command failed")
            var raw = [UInt16](repeating:0,count:4)
            raw.withUnsafeMutableBytes { bytes in texture.getBytes(bytes.baseAddress!, bytesPerRow:8,from:MTLRegionMake2D(x,y,1,1),mipmapLevel:0) }
            return raw.map { Float(Float16(bitPattern:$0)) }
        }
        let sdr = try pixel(headroom:1,x:128,y:32), hdr = try pixel(headroom:1.6,x:128,y:32)
        precondition(abs(sdr[3] - 0.50) < 0.002 && abs(hdr[3] - sdr[3]) < 0.002,
            "More backdrop must transmit without fading the independent HDR light")
        let backdropDifference = (1 - hdr[3]) * (0.9 - 0.2)
        precondition(backdropDifference > 0.34, "Glass backdrop contrast must survive the highlight")
        let sdrComposite = sdr[2]+(1-sdr[3])*0.9
        let hdrComposite = hdr[2]+(1-hdr[3])*0.9
        precondition(sdrComposite <= 1.001)
        precondition(hdrComposite > 1.15, "EDR must produce actual above-reference-white light")
        precondition(hdr[2]/hdr[3] > 1.4, "Float surface must retain extended-range color")
        let red = hdr[0]+(1-hdr[3])*0.9, green = hdr[1]+(1-hdr[3])*0.9
        precondition(red / hdrComposite > 0.72, "HDR should not return to highly saturated cyan")
        precondition(abs(green - hdrComposite) < 0.07, "Keep a restrained blue-green light tint")
        let corner = try pixel(headroom:1.6,x:0,y:0)
        precondition(corner[3] < 0.01, "Rounded corners must remain transparent")
        let pearlSDR = try pixel(headroom:1,x:128,y:32,material:.pearl)
        let pearlHDR = try pixel(headroom:1.3,x:128,y:32,material:.pearl)
        let pearlComposite = pearlHDR[0] + (1-pearlHDR[3])*0.9
        precondition(pearlSDR[0] / pearlSDR[3] <= 1.001)
        precondition(pearlComposite > 1.05 && pearlComposite < hdrComposite,
            "Pearl must emit real HDR light, more softly than celadon")
        precondition(pearlHDR[0] / pearlHDR[3] <= 1.301, "Pearl must stay within its own 1.3 ceiling")
        let warmTop = try pixel(headroom:1,x:128,y:8,material:.pearl)
        let warmBottom = try pixel(headroom:1,x:128,y:55,material:.pearl)
        precondition(warmTop[2]/warmTop[3] < warmBottom[2]/warmBottom[3],
            "Top must be subtly warmer than bottom, independently of opacity")
        let litTop = try pixel(headroom:1.3,x:128,y:8,material:.pearl)
        let litBottom = try pixel(headroom:1.3,x:128,y:55,material:.pearl)
        precondition(litTop[2]/litTop[0] < litBottom[2]/litBottom[0],
            "EDR must preserve the subtle warm gradient rather than clipping it to neutral white")
        let pearlDark = try pixel(headroom:1.3,x:128,y:32,material:.pearl,dark:1)
        precondition(pearlDark[0] + (1-pearlDark[3])*0.04 < 0.25, "Dark pearl must preserve white-text contrast")
        print("PASS: pearl real EDR composite \(pearlComposite), independent 1.3 ceiling, warm-top gradient and dark contrast")
        let markerSDR = try pixel(headroom:1,x:128,y:32,material:.marker)
        let markerHDR = try pixel(headroom:1.3,x:128,y:32,material:.marker)
        let markerComposite = markerHDR[2] + (1-markerHDR[3])*0.9
        precondition(markerComposite > 1.25 && markerComposite <= 1.301, "Solid blue must retain actual EDR blue-channel output")
        precondition(markerHDR[3] == 1 && markerSDR[3] == 1, "Blue body must be opaque")
        precondition(markerHDR[0] < 0.001 && markerHDR[1] < markerHDR[2] * 0.1,
            "EDR must preserve deep blue instead of adding neutral white")
        let mark = try pixel(headroom:1.3,x:4,y:32,material:.marker)
        precondition(zip(mark,markerHDR).allSatisfy { abs($0-$1) < 0.001 }, "No separate left bookmark may remain")
        let luminance = markerHDR[0]*0.2126 + markerHDR[1]*0.7152 + markerHDR[2]*0.0722
        precondition(1.05/(luminance+0.05) > 4.5, "White text must retain sufficient contrast on HDR blue")
        let markerDark = try pixel(headroom:1.3,x:128,y:32,material:.marker,dark:1)
        precondition(zip(markerDark,markerHDR).allSatisfy { abs($0-$1) < 0.001 }, "Solid blue must be consistent across appearances")
        let markerCorner = try pixel(headroom:1.3,x:0,y:0,material:.marker)
        precondition(markerCorner[3] < 0.01)
        print("PASS: marker body EDR composite \(markerComposite), 1.3 ceiling, opaque blue, no bookmark, white-text contrast and rounded corners")
        print("PASS: Metal float rendering; SDR composite \(sdrComposite), EDR composite \(hdrComposite); transparent corners")
        // Exercise the real CAMetalLayer/Window path, then close the test window.
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 320, height: 80),
            styleMask: .borderless, backing: .buffered, defer: false)
        let view = HDRSelectionView(frame: NSRect(x: 0,y:0,width:320,height:80))
        window.contentView = view; view.active = true
        view.layoutSubtreeIfNeeded()
        precondition(view.glowLayer.shadowOffset == .zero && view.glowLayer.shadowRadius == 3,
            "Halo must be soft and symmetric, not a directional drop shadow")
        let mask = view.glowLayer.mask as! CAShapeLayer
        let source = NSColor(cgColor: view.glowLayer.fillColor!)!.usingColorSpace(.sRGB)!
        precondition(source.alphaComponent <= 0.121 && source.redComponent > 0.4,
            "Antialiased mask seams must not expose an opaque black source")
        precondition(view.glowLayer.shadowPath != nil, "Explicit shadow silhouette must preserve the halo")
        precondition(view.glowLayer.contentsScale == window.backingScaleFactor && mask.contentsScale == window.backingScaleFactor,
            "Halo and hollow mask must render at native backing resolution, not 1x on Retina")
        precondition(mask.fillRule == .evenOdd)
        precondition(!mask.path!.contains(CGPoint(x: 170, y: 50), using: .evenOdd),
            "Halo must not change the material inside the candidate")
        precondition(mask.path!.contains(CGPoint(x: 8, y: 50), using: .evenOdd),
            "Halo must be allowed outside the candidate")
        precondition(view.glowLayer.superlayer === view.metalLayer.superlayer,
            "Halo must not wrap and flatten the HDR Metal layer")
        window.level = .floating
        window.center()
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.finishLaunching()
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.03), inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
            NSApp.updateWindows()
        }
        precondition(view.metalLayer.wantsExtendedDynamicRangeContent == true, "Visible window must request EDR")
        for screen in NSScreen.screens {
            print("DISPLAY: \(screen.localizedName), current EDR \(screen.maximumExtendedDynamicRangeColorComponentValue), potential \(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)")
        }
        view.active = false
        precondition(view.metalLayer.wantsExtendedDynamicRangeContent == false)
        window.orderOut(nil)
        print("PASS: native EDR window activation and release")
    }
}
