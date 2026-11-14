import AppKit

@main struct BrandAboutTests {
    static func main() {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        for variant in ["light","dark"] {
            let rep = NSPDFImageRep(data: try! Data(contentsOf: root.appendingPathComponent("AboutBrand-\(variant).pdf")))!
            precondition(rep.pageCount == 1 && rep.size == NSSize(width:520,height:160))
            let view = BrandAboutView(frame:NSRect(x:0,y:0,width:440,height:186),resources:root)
            precondition(abs(view.artworkRect.width / view.artworkRect.height - 520.0 / 160.0) < 0.001)
            precondition(view.artworkRect.midX == view.bounds.midX && view.artworkRect.midY == view.bounds.midY)
            precondition(view.bounds.contains(view.artworkRect))
            view.appearance = NSAppearance(named:variant == "dark" ? .darkAqua : .aqua)
            precondition(view.hitTest(.zero) == nil)
            precondition(view.accessibilityLabel()?.contains("Meet&See") == true)
            let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds)!
            view.cacheDisplay(in:view.bounds,to:bitmap)
            precondition(bitmap.pixelsWide > 0)
        }
        print("PASS: light/dark settings brand PDF, layout, accessibility and rendering")
    }
}
