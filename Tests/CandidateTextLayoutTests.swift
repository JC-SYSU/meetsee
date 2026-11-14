import AppKit

@main struct CandidateTextLayoutTests {
    static func main() {
        _ = NSApplication.shared
        let families = ["Maple Mono NF CN", "PingFang SC", "Helvetica Neue", "Menlo"]
        var tested = 0
        for family in families {
            guard let titleFont = NSFont(name: family, size: 18), let pathFont = NSFont(name: family, size: 12) else { continue }
            tested += 1
            var offsets: [CGFloat] = []
            for text in ["旅行计划.docx", "Demo 123.txt", "gyp ÅÉ 中文.app"] {
                let title = NSTextField(labelWithString: text)
                title.frame = NSRect(x: 60, y: 6, width: 500, height: 25); title.font = titleFont
                let path = NSTextField(labelWithString: "~/Documents/Example/" + text)
                path.frame = NSRect(x: 60, y: 33, width: 500, height: 20); path.font = pathFont
                let oldBaselineGap = path.frame.minY + path.firstBaselineOffsetFromTop - title.frame.minY - title.firstBaselineOffsetFromTop
                CandidateTextLayout.center(name: title, path: path, in: NSRect(x: 0, y: 0, width: 600, height: 60))
                let a = CandidateTextLayout.typographicBounds(title), b = CandidateTextLayout.typographicBounds(path)
                precondition(abs((a.lowerBound + b.upperBound) / 2 - 30) < 0.001)
                precondition(abs(path.frame.minY - title.frame.minY - 27) < 0.001)
                let newBaselineGap = path.frame.minY + path.firstBaselineOffsetFromTop - title.frame.minY - title.firstBaselineOffsetFromTop
                precondition(abs(newBaselineGap - oldBaselineGap) < 0.001)
                precondition(a.lowerBound >= 0 && b.upperBound <= 60)
                precondition(title.frame.height == 25 && path.frame.height == 20)
                offsets.append(title.frame.minY)
                let before = title.frame
                CandidateTextLayout.center(name: title, path: path, in: NSRect(x: 0, y: 0, width: 600, height: 60))
                precondition(abs(title.frame.minY - before.minY) < 0.001)
            }
            precondition(offsets.allSatisfy { abs($0 - offsets[0]) < 0.001 })
        }
        precondition(tested >= 3)
        print("PASS: candidate typography centered across \(tested) fonts; line spacing, dimensions, content-independent positioning and idempotence preserved")
    }
}
