import AppKit
import SwiftUI

/// Geometry only: the interface remains AppKit. Use Apple's public continuous
/// RoundedRectangle path rather than a circular arc or a hand-tuned superellipse.
enum ContinuousCorners {
    static func path(in rect: CGRect, radius: CGFloat) -> CGPath {
        guard rect.width > 0, rect.height > 0 else { return CGMutablePath() }
        return RoundedRectangle(cornerRadius: max(0, min(radius, min(rect.width, rect.height) / 2)),
                                style: .continuous).path(in: rect).cgPath
    }
    static func bezier(in rect: CGRect, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(cgPath: path(in: rect, radius: radius))
    }

    private struct Curve {
        let a, b, c, d: CGPoint
        func point(_ t: CGFloat) -> CGPoint {
            let s = 1 - t
            return CGPoint(x: s*s*s*a.x + 3*s*s*t*b.x + 3*s*t*t*c.x + t*t*t*d.x,
                           y: s*s*s*a.y + 3*s*s*t*b.y + 3*s*t*t*c.y + t*t*t*d.y)
        }
        func halves() -> (Curve, Curve) {
            func mid(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x+q.x)/2, y: (p.y+q.y)/2) }
            let ab = mid(a,b), bc = mid(b,c), cd = mid(c,d)
            let abc = mid(ab,bc), bcd = mid(bc,cd), m = mid(abc,bcd)
            return (Curve(a:a,b:ab,c:abc,d:m), Curve(a:m,b:bcd,c:cd,d:d))
        }
    }
    private static func curves(_ path: CGPath) -> [Curve] {
        var result: [Curve] = [], current = CGPoint.zero, start = CGPoint.zero
        func line(to end: CGPoint) {
            if current != end {
                result.append(Curve(a:current,
                    b:CGPoint(x:(2*current.x+end.x)/3,y:(2*current.y+end.y)/3),
                    c:CGPoint(x:(current.x+2*end.x)/3,y:(current.y+2*end.y)/3),d:end))
            }
            current = end
        }
        path.applyWithBlock { ptr in
            let e = ptr.pointee
            switch e.type {
            case .moveToPoint: current = e.points[0]; start = current
            case .addLineToPoint: line(to: e.points[0])
            case .addCurveToPoint:
                result.append(Curve(a:current,b:e.points[0],c:e.points[1],d:e.points[2])); current=e.points[2]
            case .addQuadCurveToPoint:
                let q=e.points[0], end=e.points[1]
                result.append(Curve(a:current,b:CGPoint(x:(current.x+2*q.x)/3,y:(current.y+2*q.y)/3),
                    c:CGPoint(x:(end.x+2*q.x)/3,y:(end.y+2*q.y)/3),d:end)); current=end
            case .closeSubpath: line(to:start)
            @unknown default: break
            }
        }
        return result
    }
    /// Preserve the orbit's upper-left seam without replacing native curves by arcs.
    static func orbit(in rect: CGRect, radius: CGFloat) -> CGPath {
        let native = path(in: rect, radius: radius), segments = curves(native)
        guard !segments.isEmpty else { return native }
        let target = CGPoint(x:rect.minX+radius*0.3, y:rect.maxY-radius*0.3)
        let index = segments.indices.min { i,j in
            let p=segments[i].point(0.5), q=segments[j].point(0.5)
            return hypot(p.x-target.x,p.y-target.y) < hypot(q.x-target.x,q.y-target.y)
        }!
        let (left,right) = segments[index].halves()
        let ordered = [right] + Array(segments.dropFirst(index+1)) + Array(segments.prefix(index)) + [left]
        let result=CGMutablePath(); result.move(to:right.a)
        for curve in ordered { result.addCurve(to:curve.d, control1:curve.b, control2:curve.c) }
        result.closeSubpath(); return result
    }
    static func length(of path: CGPath) -> CGFloat {
        curves(path).reduce(0) { sum,curve in
            var value: CGFloat = 0, previous=curve.a
            for i in 1...32 { let p=curve.point(CGFloat(i)/32); value += hypot(p.x-previous.x,p.y-previous.y); previous=p }
            return sum+value
        }
    }

    /// Signed distance and outward normal for the exact same native contour.
    /// Cubics are sampled only in the corner region; straight edges stay analytic.
    /// This drives both ceramic bevels and the Metal mask, avoiding divergent SDFs.
    struct Field {
        struct Sample { let distance, nx, ny: Double }
        private struct Line { let ax, ay, dx, dy, squared: Double }
        private let width, height, extent: Double
        private let contour: CGPath
        private let lines: [Line]
        init(size: CGSize, radius: CGFloat) {
            width=Double(size.width); height=Double(size.height)
            extent=Double(max(0,min(radius,min(size.width,size.height)/2)))*2
            contour=ContinuousCorners.path(in:CGRect(origin:.zero,size:size),radius:radius)
            var result: [Line] = []
            for curve in ContinuousCorners.curves(contour) {
                var previous=curve.a
                for i in 1...32 {
                    let p=curve.point(CGFloat(i)/32)
                    if min(previous.x,p.x) <= size.width/2 && min(previous.y,p.y) <= size.height/2 {
                        let dx=Double(p.x-previous.x), dy=Double(p.y-previous.y)
                        if dx*dx+dy*dy > 1e-14 {
                            result.append(Line(ax:Double(previous.x),ay:Double(previous.y),dx:dx,dy:dy,squared:dx*dx+dy*dy))
                        }
                    }
                    previous=p
                }
            }
            lines=result
        }
        func sample(x: Double, y: Double) -> Sample {
            let px=min(x,width-x), py=min(y,height-y)
            let sx=x < width/2 ? 1.0 : -1.0, sy=y < height/2 ? 1.0 : -1.0
            if px >= extent || py >= extent || extent == 0 {
                return px < py ? Sample(distance:-px,nx:-sx,ny:0) : Sample(distance:-py,nx:0,ny:-sy)
            }
            var closest=Double.infinity, vx=0.0, vy=0.0, normalX=0.0, normalY=0.0
            for line in lines {
                let t=max(0,min(1,((px-line.ax)*line.dx+(py-line.ay)*line.dy)/line.squared))
                let dx=px-line.ax-t*line.dx, dy=py-line.ay-t*line.dy
                let squared=dx*dx+dy*dy
                if squared < closest {
                    closest=squared; vx=dx; vy=dy
                    normalX=line.dy; normalY = -line.dx
                }
            }
            let distance=sqrt(closest)
            let sign=contour.contains(CGPoint(x:px,y:py)) ? -1.0 : 1.0
            if distance < 1e-9 {
                let length=hypot(normalX,normalY)
                return Sample(distance:0,nx:normalX/length*sx,ny:normalY/length*sy)
            }
            return Sample(distance:distance*sign,nx:vx/distance*sign*sx,ny:vy/distance*sign*sy)
        }
    }
}

/// NSBox still manages keycap content/layout; only its circular custom bezel is replaced.
final class ContinuousKeycapBox: NSBox {
    override func draw(_ dirtyRect: NSRect) {
        let shape=ContinuousCorners.bezier(in:bounds.insetBy(dx:borderWidth/2,dy:borderWidth/2),radius:cornerRadius)
        fillColor.setFill(); shape.fill()
        borderColor.setStroke(); shape.lineWidth=borderWidth; shape.stroke()
    }
}
