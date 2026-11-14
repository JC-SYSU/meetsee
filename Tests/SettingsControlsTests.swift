import AppKit

private final class Receiver: NSObject {
    var count = 0
    @objc func changed(_ sender: Any?) { count += 1 }
}

@main struct SettingsControlsTests {
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        let receiver = Receiver()
        func checkHit(_ button: NSButton) {
            for point in [NSPoint(x: 1, y: 1), NSPoint(x: button.bounds.midX, y: button.bounds.midY), NSPoint(x: button.bounds.maxX - 1, y: button.bounds.maxY - 1)] {
                let event = NSEvent.mouseEvent(with: .leftMouseDown, location: button.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                precondition(button.cell!.hitTest(for: event, in: button.bounds, of: button).contains(.trackableArea) == button.isEnabled)
            }
            let outside = NSEvent.mouseEvent(with: .leftMouseDown, location: button.convert(NSPoint(x: -1, y: 10), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            precondition(button.cell!.hitTest(for: outside, in: button.bounds, of: button).isEmpty)
        }
        let action = SettingsActionButton(title: "添加目录…", target: receiver, action: #selector(Receiver.changed(_:)))
        action.frame = NSRect(x: 20, y: 20, width: 130, height: 30)
        window.contentView!.addSubview(action)
        checkHit(action); action.performClick(nil); precondition(receiver.count == 1)
        action.isEnabled = false; checkHit(action); action.performClick(nil); precondition(receiver.count == 1)
        action.isEnabled = true
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            action.appearance = NSAppearance(named: appearance)
            for prominent in [false, true] {
                action.prominent = prominent
                for enabled in [false, true] {
                    action.isEnabled = enabled
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 130, pixelsHigh: 30, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                    action.effectiveAppearance.performAsCurrentDrawingAppearance { action.draw(action.bounds) }
                    NSGraphicsContext.restoreGraphicsState()
                    let color = bitmap.colorAt(x: 65, y: 4)!.usingColorSpace(.sRGB)!
                    precondition(color.alphaComponent > 0)
                    if prominent && enabled {
                        precondition(abs(color.redComponent - 41 / 255) < 0.02 && abs(color.blueComponent - 77 / 255) < 0.02)
                    }
                }
            }
        }
        action.isEnabled = true
        action.keyEquivalent = "\r"
        let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        precondition(action.performKeyEquivalent(with: enter)); precondition(receiver.count == 2)
        action.removeFromSuperview()
        for labels in [["白名单", "黑名单"], ["仅名称", "名称与完整路径"], ["窄", "中", "宽"], ["3", "4", "5", "6", "7", "8"]] {
            let group = SettingsSegmentedControl(labels: labels, selected: 0, frame: NSRect(x: 20, y: 20, width: 400, height: 28))
            group.target = receiver; group.action = #selector(Receiver.changed(_:))
            window.contentView!.addSubview(group)
            group.setLabel("已更新", forSegment: 0)
            precondition(group.buttons[0].title == "已更新")
            for (index, button) in group.buttons.enumerated() {
                let before = receiver.count
                checkHit(button); button.performClick(nil)
                precondition(receiver.count == before + 1 && group.selectedSegment == index)
                precondition(group.buttons.filter { $0.state == .on }.count == 1)
            }
            group.moveSelection(from: labels.count - 1, step: 1)
            precondition(group.selectedSegment == 0)
            group.moveSelection(from: 0, step: -1)
            precondition(group.selectedSegment == labels.count - 1)
            group.selectedSegment = 0
            precondition(group.buttons[0].state == .on && group.buttons.dropFirst().allSatisfy { $0.state == .off })
            group.isEnabled = false
            let before = receiver.count
            for button in group.buttons { checkHit(button); button.performClick(nil) }
            precondition(receiver.count == before && group.selectedSegment == 0)
            group.isEnabled = true
            group.setFrameSize(NSSize(width: 250, height: 28)); group.layout()
            precondition(abs(group.buttons.last!.frame.maxX - group.bounds.width) < 0.01)
            group.removeFromSuperview()
        }
        print("PASS: full-area hits, outside/disabled exclusion, one action per click, Return key, single selection, arrow-navigation wrap, programmatic selection and resize")
        print("PASS: light/dark enabled/disabled button rendering and dynamic segment labels")
        let enterHover = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, trackingNumber: 0, userData: nil)!
        func sample(_ button: SettingsActionButton, at point: NSPoint) -> NSColor {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(button.bounds.width), pixelsHigh: Int(button.bounds.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            button.effectiveAppearance.performAsCurrentDrawingAppearance { button.draw(button.bounds) }
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.colorAt(x: Int(point.x), y: Int(point.y))!.usingColorSpace(.sRGB)!
        }
        let checkbox = SettingsCheckbox(title: "包含隐藏文件", target: receiver, action: #selector(Receiver.changed(_:)))
        checkbox.frame = NSRect(x: 20, y: 20, width: 200, height: 28)
        window.contentView!.addSubview(checkbox)
        precondition(checkbox.accessibilityRole() == .checkBox)
        let beforeCheck = receiver.count
        checkbox.performClick(nil); precondition(checkbox.state == .on && receiver.count == beforeCheck + 1)
        checkbox.performClick(nil); precondition(checkbox.state == .off && receiver.count == beforeCheck + 2)
        checkHit(checkbox)
        checkbox.isEnabled = false; checkHit(checkbox); checkbox.performClick(nil)
        precondition(checkbox.state == .off && receiver.count == beforeCheck + 2)
        checkbox.isEnabled = true
        for control in [action, checkbox] {
            control.updateTrackingAreas()
            precondition(control.trackingAreas.contains { $0.options.contains(.mouseEnteredAndExited) && $0.options.contains(.inVisibleRect) })
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                control.appearance = NSAppearance(named: appearance)
                for state in [NSControl.StateValue.off, .on, .mixed] {
                    control.state = state; control.prominent = false
                    let point = control === checkbox ? NSPoint(x: 6, y: 14) : NSPoint(x: 65, y: 4)
                    control.mouseExited(with: enterHover)
                    let rest = sample(control, at: point)
                    control.mouseEntered(with: enterHover)
                    precondition(control.isHovered)
                    let hover = sample(control, at: point)
                    precondition(abs(rest.redComponent - hover.redComponent) + abs(rest.alphaComponent - hover.alphaComponent) > 0.01, "Hover must visibly differ in both palettes and selection states")
                    control.mouseExited(with: enterHover)
                    precondition(!control.isHovered && sample(control, at: point).isEqual(rest))
                    control.isEnabled = false
                    let disabled = sample(control, at: point)
                    control.mouseEntered(with: enterHover)
                    precondition(!control.isHovered && sample(control, at: point).isEqual(disabled))
                    control.isEnabled = true
                }
            }
        }
        print("PASS: hover enter/exit pixels, disabled hover suppression, checkbox toggle/action count, full-row hits, checkbox accessibility and light/dark mixed state")
        precondition(SettingsNavigation.items.map(\.id) == ["general", "scope", "search", "pins", "diagnostics", "interaction", "appearance"])
        for (a, b) in zip(SettingsNavigation.items, SettingsNavigation.items.dropFirst()) {
            precondition(b.y - a.y >= 46)
        }
        let tabs = NSTabView()
        for id in ["general", "scope", "search", "pins", "interaction", "appearance", "diagnostics"] {
            tabs.addTabViewItem(NSTabViewItem(identifier: id))
        }
        for entry in SettingsNavigation.items {
            tabs.selectTabViewItem(withIdentifier: entry.id)
            precondition(tabs.selectedTabViewItem?.identifier as? String == entry.id)
        }
        let navigation = SettingsSidebarButton(title: "检索诊断", target: receiver, action: #selector(Receiver.changed(_:)))
        navigation.frame = NSRect(x: 20, y: 20, width: 136, height: 42)
        navigation.setButtonType(.radio)
        window.contentView!.addSubview(navigation)
        checkHit(navigation)
        let beforeNavigation = receiver.count
        navigation.performClick(nil)
        precondition(receiver.count == beforeNavigation + 1 && navigation.state == .on)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            navigation.appearance = NSAppearance(named: appearance)
            navigation.state = .on
            let marker = sample(navigation, at: NSPoint(x: 9, y: 21))
            precondition(marker.greenComponent > marker.blueComponent)
            navigation.state = .off
            navigation.mouseEntered(with: enterHover)
            let hover = sample(navigation, at: NSPoint(x: 9, y: 21))
            precondition(hover.alphaComponent < 0.2, "Hover has no opaque selection marker")
            navigation.mouseExited(with: enterHover)
            precondition(sample(navigation, at: NSPoint(x: 9, y: 21)).alphaComponent == 0)
        }
        print("PASS: grouped sidebar order, stable page identifiers, full-area navigation click, green selection marker and marker-free hover in both appearances")
    }
}
