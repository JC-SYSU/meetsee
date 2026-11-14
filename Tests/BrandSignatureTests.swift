import AppKit
@main struct BrandSignatureTests {
    static func main() {
        _ = NSApplication.shared
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        for dark in [false, true] {
            let url = source.appendingPathComponent(dark ? "Signature-dark.pdf" : "Signature-light.pdf")
            let rep = NSPDFImageRep(data: try! Data(contentsOf: url))!
            precondition(rep.pageCount == 1 && rep.size.width > rep.size.height)
        }
        precondition(BrandSignatureView.shouldShow(query: "", scanning: false))
        for query in ["", " ", "a", "旅行"] {
            precondition(!BrandSignatureView.shouldShow(query: query, scanning: true))
            if !query.isEmpty { precondition(!BrandSignatureView.shouldShow(query: query, scanning: false)) }
        }
        for width: CGFloat in [600,720,840] {
            let frame = BrandSignatureView.signatureFrame(width: width, height: 80)
            precondition(abs(width - frame.maxX) < 0.001)
            precondition(abs(frame.minY - 80 - 14) < 0.001)
            precondition(frame.width == 136)
            precondition(frame.maxY < 160)
        }
        let view = BrandSignatureView(resources: source)
        precondition(view.hitTest(.zero) == nil)
        view.update(query: "", scanning: false, animated: false)
        precondition(abs(view.alphaValue - 0.48) < 0.001)
        view.update(query: "a", scanning: false, animated: false)
        precondition(view.alphaValue == 0)
        view.update(query: "", scanning: true, animated: false)
        precondition(view.alphaValue == 0)
        print("PASS: vector PDF variants, empty/scanning visibility, margins, opacity, pointer passthrough")
    }
}
