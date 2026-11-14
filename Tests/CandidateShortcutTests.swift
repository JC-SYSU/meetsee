import AppKit

@main struct CandidateShortcutTests {
    static func main() {
        _ = NSApplication.shared
        for rows in 3...8 {
            for count in [0, 1, 2, 5, 8, 50] {
                for number in 0...9 {
                    let expected: Int? = number >= 1 && number <= min(rows, count) ? number - 1 : nil
                    precondition(CandidateNumberShortcut.row(number: number, visibleRows: rows, resultCount: count, searching: false, markedText: false, repeating: false) == expected)
                }
            }
        }
        for n in 1...8 {
            precondition(CandidateNumberShortcut.digit(characters: String(n), modifiers: .command) == n)
            precondition(CandidateNumberShortcut.digit(characters: String(n), modifiers: [.command, .numericPad]) == n)
            for flags: NSEvent.ModifierFlags in [[], .shift, [.command, .shift], [.command, .option], [.command, .control]] {
                precondition(CandidateNumberShortcut.digit(characters: String(n), modifiers: flags) == nil)
            }
        }
        for text: String? in [nil, "", "0", "9", "12", "a"] {
            precondition(CandidateNumberShortcut.digit(characters: text, modifiers: .command) == nil)
        }
        for (searching, marked, repeating) in [(true, false, false), (false, true, false), (false, false, true)] {
            precondition(CandidateNumberShortcut.row(number: 1, visibleRows: 5, resultCount: 50, searching: searching, markedText: marked, repeating: repeating) == nil)
        }
        // No viewport offset enters the API: first N remain absolute result indices.
        precondition(CandidateNumberShortcut.row(number: 5, visibleRows: 5, resultCount: 50, searching: false, markedText: false, repeating: false) == 4)
        for width: CGFloat in [572, 692, 812] {
            let cell = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 60))
            let badge = CandidateShortcutBadge(frame: NSRect(x: width - 56, y: 18, width: 44, height: 24))
            badge.autoresizingMask = [.minXMargin, .minYMargin, .maxYMargin]
            cell.addSubview(badge)
            precondition(badge.frame.midY == cell.bounds.midY && badge.hitTest(.zero) == nil)
            cell.setFrameSize(NSSize(width: width + 50, height: 62))
            precondition(abs(badge.frame.midY - cell.bounds.midY) < 0.01)
            for name in [NSAppearance.Name.aqua, .darkAqua] {
                badge.appearance = NSAppearance(named: name)
                for available in [false, true] {
                    badge.available = available
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 24, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                    badge.effectiveAppearance.performAsCurrentDrawingAppearance { badge.draw(badge.bounds) }
                    NSGraphicsContext.restoreGraphicsState()
                    precondition(bitmap.colorAt(x: 22, y: 3)!.alphaComponent > 0)
                }
            }
        }
        print("PASS: Cmd digits and keypad, 3–8 row limits, short/empty results, modifiers, debounce/IME/repeat guards, absolute indices, centered passthrough badges and light/dark drawing")
    }
}
