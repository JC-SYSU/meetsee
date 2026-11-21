import AppKit
import SwiftUI
import Metal

@main struct ContinuousCornersTests {
    static func main() throws {
        _ = NSApplication.shared
        let quadratic = CGMutablePath()
        quadratic.move(to: .zero)
        quadratic.addQuadCurve(to: CGPoint(x: 6, y: 0), control: CGPoint(x: 3, y: 3))
        quadratic.closeSubpath()
        let bezier = ContinuousCorners.legacyBezier(from: quadratic)
        var cubicPoints = [NSPoint](repeating: .zero, count: 3)
        precondition(bezier.elementCount >= 3)
        _ = bezier.element(at: 1, associatedPoints: &cubicPoints)
        precondition(cubicPoints == [CGPoint(x: 2, y: 2), CGPoint(x: 4, y: 2), CGPoint(x: 6, y: 0)])
        precondition(bezier.element(at: 2) == .closePath)

        let sizes: [(CGFloat,CGFloat,CGFloat)] = [(720,320,22),(690,58,13),(440,134,19),(144,36,8),(16,16,4),(25,13,2.5),(88,26,6)]
        var changedPixels = 0
        for (w,h,r) in sizes {
            let rect = CGRect(x:0,y:0,width:w,height:h)
            let native = RoundedRectangle(cornerRadius:r,style:.continuous).path(in:rect).cgPath
            let path = ContinuousCorners.path(in:rect,radius:r)
            precondition(path == native, "Custom drawing must use Apple's public continuous path")
            let compatible = ContinuousCorners.legacyBezier(from: path)
            let circular = CGPath(roundedRect:rect,cornerWidth:r,cornerHeight:r,transform:nil)
            let field = ContinuousCorners.Field(size:rect.size,radius:r)
            for y in stride(from:0.125,to:Double(min(h,2*r)),by:0.25) {
                for x in stride(from:0.125,to:Double(min(w,2*r)),by:0.25) {
                    let point=CGPoint(x:x,y:y), value=field.sample(x:x,y:y)
                    precondition((value.distance <= 0) == native.contains(point), "CPU/Metal distance-field sign must agree with the native contour")
                    if abs(value.distance) > 0.25 {
                        precondition(compatible.contains(point) == native.contains(point), "The macOS 13 path conversion must preserve the contour")
                    }
                    precondition(abs(hypot(value.nx,value.ny)-1) < 1e-8)
                    if circular.contains(point) != native.contains(point) { changedPixels += 1 }
                    let opposite=field.sample(x:Double(w)-x,y:Double(h)-y)
                    precondition(abs(value.distance-opposite.distance) < 1e-8, "Opposite corners must have identical curvature")
                }
            }
            let orbit = ContinuousCorners.orbit(in:rect,radius:r)
            precondition(orbit.boundingBoxOfPath == native.boundingBoxOfPath)
            precondition(abs(ContinuousCorners.length(of:orbit)-ContinuousCorners.length(of:native)) < 0.03)
            for y in stride(from:0.25,to:Double(min(h,2*r)),by:0.5) {
                for x in stride(from:0.25,to:Double(min(w,2*r)),by:0.5) {
                    precondition(orbit.contains(CGPoint(x:x,y:y)) == native.contains(CGPoint(x:x,y:y)), "Orbit seam must not alter its silhouette")
                }
            }
        }
        precondition(changedPixels > 50, "A circular arc renamed continuous is not a fix")
        print("PASS: 7 UI geometries equal native continuous paths, signed fields, unit normals, symmetric corners and unchanged orbit silhouette")

        for style in [HighlightStyle.marker, .porcelain] {
            let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:22,pixelsHigh:20,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
            SelectionPaint.draw(style,in:NSRect(x:0,y:0,width:22,height:20),dark:false,radius:6)
            NSGraphicsContext.restoreGraphicsState()
            precondition(bitmap.colorAt(x:2,y:2)!.alphaComponent > 0.95, "Swatch paint must match its 6pt mask, not a 13pt row/capsule")
        }
        print("PASS: small swatches use their own continuous radius, without a mismatched circular inner fill")

        guard let renderer=HDRSelectionRenderer.shared else { fatalError("Metal unavailable") }
        for scale in [1,2,3] {
            let width=300*scale, height=60*scale
            let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:width,height:height,mipmapped:false)
            descriptor.storageMode = .shared; descriptor.usage = .renderTarget
            let texture=renderer.device.makeTexture(descriptor:descriptor)!
            let buffer=renderer.queue.makeCommandBuffer()!
            renderer.encode(texture:texture,parameters:.init(size:SIMD2(300,60),headroom:1,dark:0,material:HDRSelectionMaterial.marker.rawValue),buffer:buffer)
            buffer.commit(); buffer.waitUntilCompleted()
            precondition(buffer.status == .completed)
            let field=ContinuousCorners.Field(size:CGSize(width:300,height:60),radius:13)
            let ceramic=PorcelainMaterial.image(.green,size:CGSize(width:300,height:60),radius:13,scale:CGFloat(scale)).representations.first as! NSBitmapImageRep
            var pixels=[UInt16](repeating:0,count:width*height*4)
            pixels.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!,bytesPerRow:width*8,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0) }
            for y in 0..<(26*scale) {
                for x in 0..<(26*scale) {
                    let d=field.sample(x:(Double(x)+0.5)/Double(scale),y:(Double(y)+0.5)/Double(scale)).distance
                    let alpha=Float(Float16(bitPattern:pixels[(y*width+x)*4+3]))
                    let t=max(0,min(1,(d+0.6/Double(scale))/(1.2/Double(scale))))
                    precondition(abs(Double(alpha)-(1-t*t*(3-2*t))) < 0.002, "HDR coverage must match the continuous field at native resolution")
                    let cpuAlpha=Double(ceramic.bitmapData![y*ceramic.bytesPerRow+x*4+3])/255
                    precondition(abs(cpuAlpha-max(0,min(1,0.5-d*Double(scale)))) < 0.005)
                }
            }
        }
        let view=HDRSelectionView(frame:NSRect(x:0,y:0,width:300,height:60)); view.layout()
        let expected=ContinuousCorners.path(in:view.glowLayer.bounds.insetBy(dx:10,dy:10),radius:13)
        precondition(view.glowLayer.path == expected && view.glowLayer.shadowPath == expected)
        print("PASS: Metal + ceramic masks at 1x/2x/3x, matching halo/shadow contour; no visible test windows")
    }
}
