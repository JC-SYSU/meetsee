import AppKit

extension AppDelegate {
    func makePinsPage() -> NSView {
        draftPins = settings.pinnedItems ?? []
        pinsDocument = TopView(frame: NSRect(x: 0, y: 0, width: 708, height: 500))
        renderPins()
        return SettingsPage(document: pinsDocument)
    }
    func renderPins() {
        pinsDocument.subviews.forEach { $0.removeFromSuperview() }
        pinsDocument.setFrameSize(NSSize(width: 708, height: max(440, 172 + draftPins.count * 80)))
        pinsDocument.addSubview(label("常用置顶", NSRect(x: 12, y: 12, width: 480, height: 32), size: 19, bold: true))
        pinsDocument.addSubview(label("输入完整检索词、全拼或首字母缩写，让常用目标优先出现。", NSRect(x: 12, y: 54, width: 530, height: 24), size: 12, color: .secondaryLabelColor))
        _ = button("＋ 添加", NSRect(x: 570, y: 16, width: 110, height: 30), #selector(addPin), in: pinsDocument)
        pinsDocument.addSubview(label("手动绑定不受白名单限制；本地目标仍遵守黑名单与系统权限。", NSRect(x: 12, y: 86, width: 680, height: 24), size: 11, color: .secondaryLabelColor))
        pinsDocument.addSubview(label("检索词", NSRect(x: 20, y: 128, width: 150, height: 22), size: 11, color: .secondaryLabelColor))
        pinsDocument.addSubview(label("置顶目标", NSRect(x: 190, y: 128, width: 360, height: 22), size: 11, color: .secondaryLabelColor))
        if draftPins.isEmpty {
            pinsDocument.addSubview(label("还没有置顶条目 · 添加一个常用文件、文件夹或网页地址。", NSRect(x: 20, y: 192, width: 660, height: 30), size: 12, color: .secondaryLabelColor))
        }
        for (index, item) in draftPins.enumerated() {
            let y = CGFloat(164 + index * 80)
            pinsDocument.addSubview(label(item.term, NSRect(x: 20, y: y + 8, width: 150, height: 26), size: 14, bold: true))
            let resolved = try? item.resolve()
            let name = resolved?.name ?? (item.displayName.isEmpty ? (item.target as NSString).lastPathComponent : item.displayName)
            let blocked = resolved?.entry.map { BlacklistFilter(settings).rejects($0) } ?? false
            let title = label(name, NSRect(x: 190, y: y, width: 350, height: 25), size: 13)
            title.toolTip = item.target; pinsDocument.addSubview(title)
            let detail = resolved == nil ? "目标失效或无权限 · 请编辑路径" : (blocked ? "被已保存的黑名单排除" : (resolved!.url.isFileURL ? resolved!.url.path : item.target))
            let path = label(detail, NSRect(x: 190, y: y + 28, width: 350, height: 22), size: 11, color: resolved == nil || blocked ? .systemOrange : .secondaryLabelColor)
            path.toolTip = detail; pinsDocument.addSubview(path)
            let edit = button("编辑", NSRect(x: 554, y: y + 8, width: 58, height: 28), #selector(editPin(_:)), in: pinsDocument); edit.tag = index
            let remove = button("移除", NSRect(x: 622, y: y + 8, width: 58, height: 28), #selector(removePin(_:)), in: pinsDocument); remove.tag = index
            let rule = NSBox(frame: NSRect(x: 20, y: y + 68, width: 660, height: 1)); rule.boxType = .separator; pinsDocument.addSubview(rule)
        }
        if settingsWindow != nil { previewThemeFont() }
    }
    @objc func addPin() { presentPinEditor(index: nil) }
    @objc func editPin(_ sender: NSButton) { presentPinEditor(index: sender.tag) }
    @objc func removePin(_ sender: NSButton) { draftPins.remove(at: sender.tag); renderPins() }
    func presentPinEditor(index: Int?) {
        guard let parent = settingsWindow else { return }
        editingPinIndex = index
        let item = index.map { draftPins[$0] }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 350), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = item == nil ? "添加常用置顶" : "编辑常用置顶"
        let body = TopView(frame: NSRect(x: 0, y: 0, width: 600, height: 350)); sheet.contentView = body
        func field(_ title: String, _ value: String, _ placeholder: String, y: CGFloat) -> NSTextField {
            body.addSubview(label(title, NSRect(x: 24, y: y, width: 120, height: 26), size: 12))
            let field = NSTextField(frame: NSRect(x: 150, y: y, width: 426, height: 28))
            field.stringValue = value; field.placeholderString = placeholder
            field.setAccessibilityLabel(title); body.addSubview(field); return field
        }
        pinTerm = field("检索词", item?.term ?? "", "中文、英文或混输", y: 28)
        pinTerm.toolTip = "中文自动支持全拼和首字母缩写（至少2字符），无需额外添加；手动检索词优先，同缩写按名单顺序。"
        let resolvedURL = try? item?.resolve().url
        let targetText = resolvedURL.map { $0.isFileURL ? $0.path : $0.absoluteString } ?? item?.target ?? ""
        pinTarget = field("置顶目标", targetText, "粘贴或输入本地路径 / https://…", y: 84)
        pinName = field("显示名称（选填）", item?.displayName ?? "", "留空时使用文件名或网页域名", y: 140)
        pinError = label("", NSRect(x: 24, y: 194, width: 552, height: 62), size: 12, color: .systemOrange)
        pinError.maximumNumberOfLines = 3; pinError.cell?.wraps = true; body.addSubview(pinError)
        body.addSubview(label("完成后需在设置页保存；取消设置会撤销本次修改。", NSRect(x: 24, y: 262, width: 550, height: 20), size: 11, color: .secondaryLabelColor))
        let cancel = button("取消", NSRect(x: 380, y: 306, width: 90, height: 28), #selector(cancelPinEditor), in: body); cancel.keyEquivalent = "\u{1b}"
        let done = button("完成", NSRect(x: 486, y: 306, width: 90, height: 28), #selector(commitPinEditor), in: body); done.keyEquivalent = "\r"
        let family = fontPopup.titleOfSelectedItem ?? settings.effectiveFontName
        for case let control as NSControl in body.subviews { control.font = NSFont(name: family, size: control.font?.pointSize ?? 12) ?? control.font }
        pinSheet = sheet; parent.beginSheet(sheet); sheet.makeFirstResponder(pinTerm)
    }
    @objc func cancelPinEditor() {
        if let sheet = pinSheet { settingsWindow?.endSheet(sheet); sheet.orderOut(nil) }
        pinSheet = nil
    }
    @objc func commitPinEditor() {
        do {
            let id = editingPinIndex.map { draftPins[$0].id } ?? UUID()
            let item = try PinnedItem.make(term: pinTerm.stringValue, target: pinTarget.stringValue, name: pinName.stringValue, id: id, others: draftPins)
            if let index = editingPinIndex { draftPins[index] = item } else { draftPins.append(item) }
            cancelPinEditor(); renderPins()
        } catch { pinError.stringValue = error.localizedDescription }
    }
}
