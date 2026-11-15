import AppKit
import Carbon
import QuartzCore
import ServiceManagement
import CoreServices

final class TopView: NSView { override var isFlipped: Bool { true } }
final class ResultsTable: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}
final class SearchPanel: NSPanel { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { true } }

// A subtle content outline, separate from the system-rendered glass and shadow.
final class GlassOutline: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        (NSColor.separatorColor.blended(withFraction: 0.12, of: .labelColor) ?? .separatorColor).setStroke()
        let outline = NSBezierPath(cgPath: SearchSurfaceGeometry.path(in: bounds))
        outline.lineWidth = 0.5
        outline.stroke()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
}

final class Ticket {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    func isCurrent(_ number: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return value == number }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var draftPins: [PinnedItem] = []
    var pinsDocument: TopView!
    var pinSheet: NSWindow?
    var editingPinIndex: Int?
    var pinTerm: NSTextField!
    var pinTarget: NSTextField!
    var pinName: NSTextField!
    var pinError: NSTextField!
    var settings = Settings()
    var entries: [Entry] = []
    var results: [SearchCandidate] = []
    private var displayedQuery: String?
    private var completedSearchGeneration = -1
    var fileSearchPending = false
    let settingsPages = SettingsDestination.available()
    var systemSettingsButton: NSButton!
    var contacts = ContactsSearch()
    var contactsSection: TopView!
    var contactsButton: NSButton!
    var contactsPermissionButton: NSButton!
    var contactsStatus: NSTextField!
    var lokiiScopeReady = false
    var modePicker: SettingsSegmentedControl!
    var lokiiDetails: NSTextField!
    var lokiiCheckButton: NSButton!
    var modeHint: NSTextField!
    var lokiiNote = "尚未检查连接"
    var lokiiRequestGeneration = 0
    var savingMode = false
    let lokiiProcess = LokiiProcess()
    lazy var lokiiEngine = LokiiEngine(process: lokiiProcess)
    var lokiiGeneration = -1
    var lokiiQueryNote = ""
    var lokiiRestarts: [Date] = []
    var lastLokiiStatusData: Data?
    let connectionQueue = DispatchQueue(label: "QuickFind.lokii-connection", qos: .userInitiated)
    var scanErrors: [String] = []
    var panel: SearchPanel!
    var glassSurface: NSView?
    var typeSelectionChanged = false
    var legacyMigrationRequested = false
    var scopeDescription: NSTextField!
    var migrationButton: NSButton!
    var extensionlessHint: NSTextField!
    var opacitySlider: NSSlider!
    var opacityValue: NSTextField!
    var input: NSTextField!
    var inputHeight: NSLayoutConstraint?
    var table: NSTableView!
    var status: NSTextField!
    var resultScroll: NSScrollView!
    let glassMargin: CGFloat = 80
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    var settingsDocument: TopView!
    var scopePage: SettingsPage!
    var scopePicker: SettingsSegmentedControl!
    var scopeOffsets: [CGFloat] = [0, 0]
    var selectedScope = 0
    var diagnosticPath: NSTextField!
    var diagnosticQuery: NSTextField!
    var diagnosticOutput: NSTextView!
    var diagnosticGeneration = 0
    let diagnosticQueue = DispatchQueue(label: "QuickFind.diagnostics", qos: .userInitiated)
    var whiteBody: TopView!
    var typeBody: TopView!
    var whiteDetails: TopView!
    var blackBody: TopView!
    var generalBody: TopView!
    var whiteToggle: NSButton!
    var blackToggle: NSButton!
    var blockedExtensionField: NSTextField!
    var blockedKeywordEditor: NSTextView!
    var aliasExclusionButton: NSButton!
    var symlinkExclusionButton: NSButton!
    var scopeList: DirectoryListView!
    var excludedList: DirectoryListView!
    var addScopeButton: NSButton!
    var addBlacklistScopeButton: NSButton!
    var scopeDirectoryLabel: NSTextField!
    var scopeDirectoryHint: NSTextField!
    var blackDirectoryLabel: NSTextField!
    var blackDirectoryHint: NSTextField!
    var blockedExtensionLabel: NSTextField!
    var blockedKeywordLabel: NSTextField!
    var blockedKeywordHint: NSTextField!
    var linkTypeLabel: NSTextField!
    var linkTypeHint: NSTextField!
    var scopeRule: NSBox!
    var extensionField: NSTextField!
    var categoryButtons: [FileKind: NSButton] = [:]
    var allButton: NSButton!
    var hiddenButton: NSButton!
    var refreshButton: NSButton!
    var extensionlessButton: NSButton!
    var visibilityGeneration = 0
    var hiding = false
    var dimmingPanel: NSPanel?
    var matchPopup: SettingsSegmentedControl!
    var sortPopup: SettingsSegmentedControl!
    var applicationsFirstButton: NSButton!
    var widthPicker: SettingsSegmentedControl!
    var rowsPicker: SettingsSegmentedControl!
    var limitPopup: SettingsSegmentedControl!
    var searchWidth: CGFloat { CGFloat(settings.effectiveWindowWidth) }
    var hotPopup: NSPopUpButton!
    var fontPopup: NSPopUpButton!
    var stylePreview: StylePreview!
    var themeButtons: [ThemeChoiceButton] = []
    var draftStyle: HighlightStyle = .mist
    var settingsTabs: NSTabView!
    var sidebarButtons: [NSButton] = []
    var signature: BrandSignatureView!
    var scanMotion: ScanMotionView!
    var scanIndicator: ScanMotionView!
    var displayObserver: NSObjectProtocol?
    // Other styles are retained in source but disabled, including legacy preferences.
    var currentMotionStyle: ScanMotionStyle { .pulse }

    var settingsSaveButton: NSButton!
    var settingsCancelButton: NSButton!
    var loginButton: NSButton!
    var loginStatusLabel: NSTextField!
    var hotKey: EventHotKeyRef?
    var hotHandler: EventHandlerRef?
    var keyboardMonitor: Any?
    let scanTicket = Ticket()
    let searchTicket = Ticket()
    let scanner = DispatchQueue(label: "QuickFind.scanner", qos: .utility)
    let searcher = DispatchQueue(label: "QuickFind.search", qos: .userInitiated)
    var pendingSearch: DispatchWorkItem?
    var indexing = false
    let resultIcons = NSCache<NSString, NSImage>()
    var commandHeld = false
    var searching = false { didSet { updateCandidateShortcutHints() } }
    var scanningPath = ""
    var lastScan: Date?
    var timer: Timer?
    var indexWatcher: IndexWatcher?
    var pendingPaths = Set<String>()
    var pendingEventID: UInt64 = 0
    var pendingFullScan = false
    var incrementalWork: DispatchWorkItem?
    var cacheWrite: DispatchWorkItem?
    var lastCalibration: Date?
    var watcherAvailable = false
    var indexMode = "全量校准"
    var shortcutError = false
    var storage: URL {
        if let override = ProcessInfo.processInfo.environment["QUICKFIND_DATA_DIR"] { return URL(fileURLWithPath: override) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QuickFind")
    }
    var indexURL: URL { storage.appendingPathComponent("IndexCache/names-v1.plist") }
    var settingsURL: URL { storage.appendingPathComponent("settings.json") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let data = try? Data(contentsOf: settingsURL), let decoded = try? JSONDecoder().decode(Settings.self, from: data) { settings = decoded; settings.limit = settings.effectiveCandidateLimit; settings.migrateCategories() }
        if let roots = ProcessInfo.processInfo.environment["QUICKFIND_ROOTS"] { settings.roots = roots.components(separatedBy: "\n") }
        NSApp.setActivationPolicy(.accessory)
        let main = NSMenu()
        let item = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "退出觅见", action: #selector(quit), keyEquivalent: "q").target = self
        item.submenu = appMenu; main.addItem(item)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editItem.submenu = edit; main.addItem(editItem)
        let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu; main.addItem(fileItem); NSApp.mainMenu = main
        buildPanel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.make()
        statusItem.button?.toolTip = "觅见 Meet&See"
        let menu = NSMenu()
        menu.addItem(withTitle: "搜索 · 觅见", action: #selector(showSearch), keyEquivalent: "").target = self
        menu.addItem(withTitle: "搜索设置…", action: #selector(showSettings), keyEquivalent: "").target = self
        menu.addItem(withTitle: "刷新名称索引", action: #selector(reindex), keyEquivalent: "").target = self
        menu.addItem(withTitle: "查看索引状态", action: #selector(showDiagnostics), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "").target = self
        statusItem.menu = menu
        registerHotKey()
        configureContacts()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                self.commandHeld = self.panel.isKeyWindow && event.modifierFlags.contains(.command)
                self.updateCandidateShortcutHints()
                return event
            }
            guard event.window === self.panel, !self.hiding else { return event }
            // Never consume arrows/return while a Chinese IME has marked text.
            if let editor = self.input.currentEditor() as? NSTextView, editor.hasMarkedText() { return event }
            if let digit = CandidateNumberShortcut.digit(characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags) {
                if let row = CandidateNumberShortcut.row(number: digit, visibleRows: self.settings.effectiveVisibleRows, resultCount: self.results.count, searching: self.searching, markedText: false, repeating: event.isARepeat) {
                    self.openResult(at: row)
                }
                return nil
            }
            let command = event.modifierFlags.contains(.command)
            if command && event.charactersIgnoringModifiers == "i" { self.showInfo(); return nil }
            if command && event.keyCode == 36 { self.reveal(); return nil }
            if command && event.modifierFlags.contains(.shift) && event.charactersIgnoringModifiers == "c" { self.copyPath(); return nil }
            if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
               event.charactersIgnoringModifiers?.lowercased() == "c", self.copyContactNumber() { return nil }
            if command && event.charactersIgnoringModifiers == "r" { self.reindex(); return nil }
            switch event.keyCode {
            case 125: self.moveSelection(1); return nil
            case 126: self.moveSelection(-1); return nil
            case 36: self.openSelected(); return nil
            case 53: self.hideSearch(); return nil
            default: return event
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self, self.settings.effectiveSearchMode == .native, self.settings.autoRefresh, !self.indexing else { return }
            if !self.watcherAvailable || Date().timeIntervalSince(self.lastCalibration ?? .distantPast) > 86400 { self.reindex() }
        }
        lokiiProcess.onStatus = { [weak self] value in DispatchQueue.main.async { self?.receiveLokiiStatus(value) } }
        lokiiProcess.onUnexpectedExit = { [weak self] in DispatchQueue.main.async { self?.lokiiExited() } }
        // Launch quietly; only explicit search actions may present the panel.
        if settings.effectiveSearchMode == .native { startNativeIndex() }
        else { synchronizeLokiiAtLaunch() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Finder/open and login launches must not interrupt the foreground app.
        return false
    }
    func applicationDidResignActive(_ notification: Notification) {
        if panel != nil { hideSearch() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        contacts.onChange = nil; contacts.setEnabled(false)
        indexWatcher?.stop(); incrementalWork?.cancel(); cacheWrite?.cancel()
        _ = scanTicket.next(); _ = searchTicket.next()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotHandler { RemoveEventHandler(hotHandler) }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        timer?.invalidate()
        connectionQueue.sync { lokiiProcess.stop() }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func label(_ text: String, _ frame: NSRect, size: CGFloat = 13, color: NSColor = .labelColor, bold: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: text); l.frame = frame; l.font = bold ? .systemFont(ofSize: size, weight: .semibold) : .systemFont(ofSize: size)
        l.textColor = color; l.lineBreakMode = .byTruncatingMiddle; return l
    }
    func button(_ title: String, _ frame: NSRect, _ action: Selector, in view: NSView) -> NSButton {
        let b = SettingsActionButton(title: title, target: self, action: action); b.frame = frame; b.prominent = action == #selector(saveSettings); view.addSubview(b); return b
    }
    func searchFont(size: CGFloat) -> NSFont {
        NSFont(name: settings.effectiveFontName, size: size)
            ?? NSFontManager.shared.font(withFamily: settings.effectiveFontName, traits: [], weight: 5, size: size)
            ?? .systemFont(ofSize: size)
    }
    func centerInputField() {
        // Keep AppKit's editor and non-editing cell in the same natural-height frame.
        // Center the control itself; do not override text drawing/selection rectangles.
        let height = min(80, input.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: searchWidth - 44, height: 80)).height ?? 44)
        inputHeight?.constant = height
    }
    func buildPanel() {
        let bounds = NSRect(x: 0, y: 0, width: searchWidth, height: 80)
        let windowBounds = bounds.insetBy(dx: -glassMargin, dy: -glassMargin)
        panel = SearchPanel(contentRect: NSRect(origin: .zero, size: windowBounds.size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "觅见 Meet&See"
        panel.isReleasedWhenClosed = false; panel.level = .floating
        // Deactivation must finish our dismissal animation before ordering out.
        panel.hidesOnDeactivate = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let view = TopView(frame: bounds)
        view.autoresizingMask = [.width, .height]
        // Native glass draws beyond its own bounds. Keep it away from the window's
        // rectangular compositor boundary instead of clipping its content or shadow.
        let host = TopView(frame: NSRect(origin: .zero, size: windowBounds.size))
        host.wantsLayer = true; host.layer?.masksToBounds = false
        panel.contentView = host
        let surfaceFrame = NSRect(x: glassMargin, y: glassMargin, width: bounds.width, height: bounds.height)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: surfaceFrame)
            glass.autoresizingMask = [.width, .height]
            glassSurface = glass
            glass.tintColor = settings.effectiveGlassTintStrength == 0 ? nil : NSColor.white.withAlphaComponent(settings.effectiveGlassTintStrength)
            glass.style = .regular; glass.cornerRadius = 22; glass.contentView = view
            host.addSubview(glass)
        } else {
            let material = NSVisualEffectView(frame: surfaceFrame)
            material.autoresizingMask = [.width, .height]
            material.material = .hudWindow; material.blendingMode = .behindWindow; material.state = .active
            material.wantsLayer = true; material.layer?.cornerRadius = 22; material.layer?.cornerCurve = .continuous; material.layer?.masksToBounds = true
            material.addSubview(view); host.addSubview(material)
        }
        let outline = GlassOutline(frame: surfaceFrame)
        outline.autoresizingMask = [.width, .height]
        outline.autoresizesSubviews = false
        host.addSubview(outline)
        scanMotion = ScanMotionView(frame: surfaceFrame); scanMotion.autoresizingMask = [.width, .height]
        host.addSubview(scanMotion)
        /* White overlay experiment retained for comparison; disabled in favor of tintColor.
        let whiteOverlay = WhiteOverlayView(frame: bounds)
        whiteOverlay.autoresizingMask = [.width, .height]
        whiteOverlay.opacity = CGFloat(settings.effectiveWhiteOverlayOpacity)
        view.addSubview(whiteOverlay, positioned: .below, relativeTo: nil)
        */
        // A borderless single-line text field avoids NSSearchField's fixed-height search cell.
        input = NSTextField(frame: NSRect(x: 22, y: 0, width: searchWidth - 44, height: 80))
        input.isEditable = true; input.isSelectable = true
        input.font = searchFont(size: 32)
        input.isBezeled = false; input.drawsBackground = false; input.focusRingType = .none
        input.cell?.usesSingleLineMode = true; input.cell?.isScrollable = true
        input.placeholderString = ""; input.setAccessibilityLabel("搜索文件、文件夹、应用和已启用的检索来源")
        input.delegate = self; view.addSubview(input)
        input.translatesAutoresizingMaskIntoConstraints = false
        inputHeight = input.heightAnchor.constraint(equalToConstant: input.intrinsicContentSize.height)
        NSLayoutConstraint.activate([
            input.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            input.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            input.centerYAnchor.constraint(equalTo: view.topAnchor, constant: 40),
            inputHeight!
        ])
        centerInputField()
        // Outside signature disabled after visual review; retain source assets.
        resultScroll = NSScrollView(frame: .zero)
        resultScroll.hasVerticalScroller = true; resultScroll.autohidesScrollers = true
        resultScroll.borderType = .noBorder; resultScroll.drawsBackground = false
        table = ResultsTable(); let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result")); column.width = searchWidth - 28
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 60; table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .plain
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self; table.delegate = self; table.target = self; table.doubleAction = #selector(openSelected)
        table.selectionHighlightStyle = .regular; table.backgroundColor = .clear
        resultScroll.documentView = table; view.addSubview(resultScroll)
        status = label("准备名称索引…", .zero, size: 11, color: .secondaryLabelColor); view.addSubview(status)
        scanIndicator = ScanMotionView(frame: NSRect(x: 22, y: 84, width: 20, height: 20))
        scanIndicator.compact = true; view.addSubview(scanIndicator)
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.syncScanMotion()
        }
        layoutResults(); panel.center()
    }
    func layoutResults() {
        syncScanMotion()
        signature?.frame = BrandSignatureView.signatureFrame(width: searchWidth, height: 80).offsetBy(dx: glassMargin, dy: glassMargin)
        signature?.update(query: input.stringValue, scanning: indexing, animated: panel.isVisible && !hiding)
        let expanded = indexing || !input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let available = max(0, panel.frame.maxY - (panel.screen?.visibleFrame.minY ?? 0) - 124 - glassMargin * 2)
        let rowsHeight = min(CGFloat(min(results.count, settings.effectiveVisibleRows)) * 62, available)
        let height: CGFloat = expanded ? 80 + rowsHeight + 32 : 80
        let old = panel.frame
        let target = NSRect(x: old.midX - searchWidth / 2 - glassMargin, y: old.maxY - height - glassMargin * 2, width: searchWidth + glassMargin * 2, height: height + glassMargin * 2)
        resultScroll.isHidden = !expanded || results.isEmpty; status.isHidden = !expanded
        let scrollFrame = NSRect(x: 12, y: 80, width: searchWidth - 24, height: rowsHeight)
        let textHeight = ceil(status.intrinsicContentSize.height)
        let statusFrame = SearchStatusLayout.textFrame(width: searchWidth, rowsHeight: rowsHeight,
            textHeight: textHeight, busy: SearchStatusLayout.busy(indexing: indexing, searching: searching || fileSearchPending))
        let indicatorFrame = NSRect(x: 22, y: 84 + rowsHeight, width: 20, height: 20)
        let animate = panel.isVisible && !hiding && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animate && abs(old.height - target.height) > 0.5 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
                resultScroll.animator().frame = scrollFrame
                status.animator().frame = statusFrame
                scanIndicator?.animator().frame = indicatorFrame
            }
        } else {
            panel.setFrame(target, display: true)
            resultScroll.frame = scrollFrame; status.frame = statusFrame
            scanIndicator?.frame = indicatorFrame
        }
    }
    @objc func showSearch() {
        input.stringValue = ""; runSearch()
        if let screen = panel.screen ?? NSScreen.main {
            panel.setFrameOrigin(searchPanelOrigin(screen: screen.frame, visible: screen.visibleFrame, margin: glassMargin, width: searchWidth))
        }
        visibilityGeneration += 1; hiding = false
        panel.contentView?.layer?.removeAnimation(forKey: "popup")
        panel.alphaValue = 0
        prepareDimmingPanel()
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(input)
        dimmingPanel?.order(.below, relativeTo: panel.windowNumber)
        commandHeld = NSEvent.modifierFlags.contains(.command); updateCandidateShortcutHints()
        animatePopup(appearing: true); syncScanMotion()
        
    }
    func prepareDimmingPanel() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        if dimmingPanel == nil {
            let dim = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            dim.title = "觅见背景遮罩"
            dim.isOpaque = false; dim.backgroundColor = .clear; dim.hasShadow = false
            let vignette = VignetteView(frame: NSRect(origin: .zero, size: screen.frame.size))
            vignette.autoresizingMask = [.width, .height]
            dim.contentView = vignette
            dim.ignoresMouseEvents = true; dim.hidesOnDeactivate = false
            dim.isReleasedWhenClosed = false
            dim.level = panel.level
            dim.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            dimmingPanel = dim
        }
        dimmingPanel?.setFrame(screen.frame, display: false)
        dimmingPanel?.alphaValue = 0
        if let dim = dimmingPanel {
            // Keep the full-screen parent stationary while the search child resizes.
            if panel.parent !== dim { dim.addChildWindow(panel, ordered: .above) }
            dim.orderFront(nil)
        }
    }
    func animatePopup(appearing: Bool, completion: (() -> Void)? = nil) {
        let duration = appearing ? 0.18 : 0.14
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = panel.contentView?.layer {
            // Scale around the input area's center, not the layer's bottom-left anchor.
            let center = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
            let scale: CGFloat = appearing ? 0.94 : 0.97
            var small = CATransform3DMakeTranslation(center.x, center.y - (appearing ? 14 : 8), 0)
            small = CATransform3DScale(small, scale, scale, 1)
            small = CATransform3DTranslate(small, -center.x, -center.y, 0)
            if appearing {
                let spring = CASpringAnimation(keyPath: "transform")
                spring.fromValue = NSValue(caTransform3D: small)
                spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
                spring.mass = 1; spring.stiffness = 280; spring.damping = 16
                spring.initialVelocity = 0
                spring.duration = spring.settlingDuration
                layer.add(spring, forKey: "popup")
            } else {
                let retreat = CABasicAnimation(keyPath: "transform")
                retreat.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? CATransform3DIdentity)
                retreat.toValue = NSValue(caTransform3D: small)
                retreat.duration = duration; retreat.timingFunction = CAMediaTimingFunction(name: .easeIn)
                retreat.fillMode = .forwards; retreat.isRemovedOnCompletion = false
                layer.add(retreat, forKey: "popup")
            }
        }
        let generation = visibilityGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: appearing ? .easeOut : .easeIn)
            panel.animator().alphaValue = appearing ? 1 : 0
            dimmingPanel?.animator().alphaValue = appearing ? 1 : 0
        } completionHandler: { [weak self] in
            // A new presentation may supersede this animation, but must not cancel
            // an already accepted candidate action or hide the newly opened panel.
            defer { completion?() }
            guard let self, self.visibilityGeneration == generation else { return }
            if !appearing {
                self.panel.orderOut(nil)
                self.dimmingPanel?.orderOut(nil)
                self.panel.alphaValue = 1
                self.panel.contentView?.layer?.removeAnimation(forKey: "popup")
                self.hiding = false
            }
        }
    }
    func hideSearch(completion: (() -> Void)? = nil) {
        pendingSearch?.cancel(); _ = searchTicket.next(); searching = false; fileSearchPending = false
        commandHeld = false; updateCandidateShortcutHints()
        guard !hiding else { return }
        guard panel.isVisible else { completion?(); return }
        visibilityGeneration += 1; hiding = true; syncScanMotion()
        animatePopup(appearing: false, completion: completion)
    }
    func registerHotKey() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if hotHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, context -> OSStatus in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { if app.panel.isKeyWindow && !app.hiding { app.hideSearch() } else { app.showSearch() } }
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotHandler)
        }
        if settings.hotKey == 2 { shortcutError = false; return }
        let modifiers: UInt32
        switch settings.hotKey {
        case 0: modifiers = UInt32(controlKey | optionKey)
        case 1: modifiers = UInt32(controlKey | shiftKey)
        default: modifiers = UInt32(cmdKey)
        }
        let code = RegisterEventHotKey(UInt32(kVK_Space), modifiers, EventHotKeyID(signature: 0x51464E44, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        shortcutError = code != noErr
    }
    func startNativeIndex() {
        let cached = IndexSnapshot.load(from: indexURL, settings: settings)
        entries = cached?.entries ?? []; lastScan = cached?.updated; lastCalibration = cached?.calibrated
        let current = FSEventsGetCurrentEventId()
        let cursor = cached?.eventID
        let canReplay = cursor != nil && cursor! <= current && cached?.calibrated != nil
            && Date().timeIntervalSince(cached!.calibrated!) < 86400
        configureIndexWatcher(since: canReplay ? cursor! : current)
        if !canReplay || !watcherAvailable { reindex() }
    }
    func stopNativeIndex() {
        _ = scanTicket.next()
        indexWatcher?.stop(); indexWatcher = nil; watcherAvailable = false
        incrementalWork?.cancel(); cacheWrite?.cancel()
        pendingPaths.removeAll(); pendingFullScan = false; pendingEventID = 0
        indexing = false; entries = []; scanErrors = []; lastScan = nil; lastCalibration = nil
    }
    @objc func reindex() {
        guard settings.effectiveSearchMode == .native else {
            searcher.async { [weak self] in self?.lokiiEngine.reset() }
            connectionQueue.async { [weak self] in
                guard let self else { return }
                do { try self.lokiiProcess.rebuild() }
                catch { DispatchQueue.main.async { [weak self] in self?.lokiiNote = error.localizedDescription; self?.updateStatus() } }
            }
            return
        }
        cacheWrite?.cancel(); incrementalWork?.cancel()
        pendingPaths.removeAll(); pendingFullScan = false
        let startID = FSEventsGetCurrentEventId()
        indexMode = "全量校准"
        let number = scanTicket.next(); let snapshot = settings; let ticket = scanTicket; let cacheURL = indexURL
        indexing = true; updateStatus(); layoutResults()
        scanner.async { [weak self] in
            let result = scan(snapshot, cancelled: { !ticket.isCurrent(number) }, progress: { partial, root in
                DispatchQueue.main.async {
                    guard let self, ticket.isCurrent(number) else { return }
                    self.scanningPath = root
                    if self.lastScan == nil { self.entries = partial; self.runSearch() }
                    self.updateStatus()
                }
            })
            guard !result.cancelled, ticket.isCurrent(number) else { return }
            let updated = Date()
            var cacheError: String?
            // Never persist a partial or failed traversal as a complete index.
            if result.errors.isEmpty {
                do { try IndexSnapshot.save(result.entries, settings: snapshot, updated: updated, eventID: startID, calibrated: updated, to: cacheURL) }
                catch { cacheError = "索引缓存未保存：\(error.localizedDescription)" }
            }
            DispatchQueue.main.async {
                guard let self, ticket.isCurrent(number) else { return }
                self.entries = result.entries; self.scanErrors = result.errors; self.lastScan = updated; self.lastCalibration = result.errors.isEmpty ? updated : self.lastCalibration; self.indexing = false
                if let cacheError { self.scanErrors.append(cacheError) }
                self.runSearch(); self.scheduleIndexChanges()
            }
        }
    }
    func configureIndexWatcher(since: UInt64) {
        indexWatcher?.stop(); incrementalWork?.cancel(); cacheWrite?.cancel()
        pendingPaths.removeAll(); pendingFullScan = false
        watcherAvailable = false
        guard settings.effectiveSearchMode == .native, settings.autoRefresh else { return }
        let watcher = IndexWatcher { [weak self] paths, eventID, fallback, _ in
            guard let self, self.settings.effectiveSearchMode == .native else { return }
            self.pendingEventID = max(self.pendingEventID, eventID)
            let cacheDirectory = expandedPath(self.indexURL.deletingLastPathComponent().path)
            self.pendingPaths.formUnion(relevantIndexEventPaths(paths, settings: self.settings, ignored: cacheDirectory))
            self.pendingFullScan = self.pendingFullScan || fallback || self.pendingPaths.count > 2000
            self.scheduleIndexChanges()
        }
        indexWatcher = watcher
        watcherAvailable = watcher.start(roots: IndexScope(settings).roots, since: since)
    }
    func scheduleIndexChanges() {
        guard settings.effectiveSearchMode == .native, settings.autoRefresh, !indexing, pendingFullScan || !pendingPaths.isEmpty else { return }
        incrementalWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyIndexChanges() }
        incrementalWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
    func applyIndexChanges() {
        guard settings.effectiveSearchMode == .native, !indexing else { return }
        if pendingFullScan { reindex(); return }
        let snapshot = settings
        let directories = affectedIndexDirectories(paths: Array(pendingPaths), roots: IndexScope(snapshot).roots,
            ignored: expandedPath(indexURL.deletingLastPathComponent().path))
        pendingPaths.removeAll()
        guard !directories.isEmpty else { return }
        let number = scanTicket.next(); let ticket = scanTicket
        let oldEntries = entries; let eventID = pendingEventID
        indexMode = "增量更新"; indexing = true; updateStatus(); layoutResults()
        scanner.async { [weak self] in
            let changed = scanIndexChanges(directories, settings: snapshot, cancelled: { !ticket.isCurrent(number) })
            guard !changed.cancelled else { return }
            let dataChanged = changed.errors.isEmpty && indexReplacementHasChanges(oldEntries, replacement: changed.entries, directories: directories)
            let merged = dataChanged ? mergingIndex(oldEntries, replacement: changed.entries, directories: directories) : oldEntries
            DispatchQueue.main.async {
                guard let self, ticket.isCurrent(number) else { return }
                self.indexing = false
                if changed.errors.isEmpty {
                    self.entries = merged; self.lastScan = Date(); self.scanErrors = []
                    self.scheduleCacheWrite(eventID: eventID)
                } else {
                    // Keep old results and checkpoint when access failed; retry via calibration.
                    self.scanErrors = changed.errors; self.lastCalibration = nil
                }
                if dataChanged { self.runSearch() }
                else { self.updateStatus(); self.layoutResults() }
                self.scheduleIndexChanges()
            }
        }
    }
    func scheduleCacheWrite(eventID: UInt64) {
        cacheWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.settings.effectiveSearchMode == .native, !self.indexing else { return }
            let entries = self.entries; let settings = self.settings; let url = self.indexURL
            let updated = self.lastScan ?? Date(); let calibrated = self.lastCalibration
            let ticket = self.scanTicket; let generation = ticket.next()
            self.scanner.async { [weak self] in
                guard ticket.isCurrent(generation) else { return }
                do { try IndexSnapshot.save(entries, settings: settings, updated: updated, eventID: eventID, calibrated: calibrated, to: url) }
                catch { DispatchQueue.main.async { [weak self] in
                    self?.scanErrors.append("索引缓存未保存：\(error.localizedDescription)"); self?.updateStatus()
                } }
            }
        }
        cacheWrite = work
        // Batch disk snapshots rather than rewriting a large cache for every edit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }
    func controlTextDidChange(_ obj: Notification) { runSearch() }
    func runSearch() {
        contacts.refreshAuthorization()
        pendingSearch?.cancel(); fileSearchPending = false
        if (input.currentEditor() as? NSTextView)?.hasMarkedText() == true {
            _ = searchTicket.next(); searching = true; return
        }
        searching = true
        // Keep the last layout during debounce; actions are gated by searching.
        if input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = []; displayedQuery = nil; table.reloadData()
        }
        if !indexing { status.stringValue = "搜索中…" }
        let number = searchTicket.next(); let query = input.stringValue; let snapshot = settings; let source = entries
        let people = settings.searchContacts == true ? contacts.index.search(query) : []
        let scopeReady = lokiiScopeReady; let scopeNote = lokiiNote
        layoutResults()
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searching = false; updateStatus(); return
        }
        if !people.isEmpty {
            // Independent of the serial file-search queue: an older slow request
            // must not delay an exact contact. A final response always wins.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.30) { [weak self] in
                guard let self, self.searchTicket.isCurrent(number) else { return }
                let empty = SearchResult(entries: [], total: 0)
                let local = mergeSettings(empty, pages: self.settingsPages, query: query, settings: snapshot, contacts: people)
                let pinned = mergePinned(local, files: empty, query: query, settings: snapshot)
                DispatchQueue.main.async {
                    guard self.searchTicket.isCurrent(number), self.completedSearchGeneration != number else { return }
                    self.presentCandidates(pinned, query: query, pendingFiles: true)
                }
            }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.searchTicket.isCurrent(number) else { return }
            let found: SearchResult
            let activeSource: [Entry]
            var externalNote: String?
            if snapshot.effectiveSearchMode == .lokii {
                do {
                    guard scopeReady else { throw LokiiError(message: scopeNote) }
                    let response = try self.lokiiEngine.searchFiles(query: query, settings: snapshot, cancelled: { !self.searchTicket.isCurrent(number) })
                    found = response.files; activeSource = response.source; externalNote = response.note
                } catch {
                    found = SearchResult(entries: [], total: 0); activeSource = []
                    externalNote = error.localizedDescription + " · 可在搜索行为切回原生"
                }
            } else {
                found = search(source, query: query, settings: snapshot, cancelled: { !self.searchTicket.isCurrent(number) })
                activeSource = source
            }
            let base = mergeSettings(found, pages: self.settingsPages, query: query, settings: snapshot, contacts: people)
            let merged = mergePinned(base, files: found, query: query, settings: snapshot, source: activeSource)
            DispatchQueue.main.async {
                guard self.searchTicket.isCurrent(number) else { return }
                self.completedSearchGeneration = number
                if let externalNote { self.lokiiQueryNote = externalNote }
                self.presentCandidates(merged, query: query)
            }
        }
        pendingSearch = work; searcher.asyncAfter(deadline: .now() + 0.30, execute: work)
    }
    func presentCandidates(_ merged: (items: [SearchCandidate], total: Int, warning: String?), query: String, pendingFiles: Bool = false) {
        fileSearchPending = pendingFiles
        let selection = displayedQuery == query && results.indices.contains(table.selectedRow)
            ? results[table.selectedRow].selectionIdentity : nil
        let changedRows = candidateRowsNeedingReload(results, merged.items)
        displayedQuery = query; searching = false; results = merged.items
        if let changedRows {
            if !changedRows.isEmpty { table.reloadData(forRowIndexes: changedRows, columnIndexes: IndexSet(integer: 0)) }
        } else { table.reloadData() }
        if !results.isEmpty {
            let row = selection.flatMap { identity in results.firstIndex { $0.selectionIdentity == identity } } ?? 0
            if table.selectedRow != row { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        }
        updateStatus(total: merged.total)
        if let warning = merged.warning { status.stringValue += " · " + warning }
        layoutResults()
    }
    func configureContacts(requestPermission: Bool = false) {
        contacts.onChange = { [weak self] in
            guard let self else { return }
            self.updateContactsControls()
            if self.panel?.isVisible == true && !self.hiding { self.runSearch() }
            else {
                // Invalidate captured snapshots as well as visible cells: a late
                // file response must not restore phone data after revoke/disable.
                _ = self.searchTicket.next(); self.pendingSearch?.cancel()
                self.searching = false; self.fileSearchPending = false
                self.results.removeAll { $0.contact != nil }; self.table?.reloadData()
            }
        }
        contacts.setEnabled(settings.searchContacts == true)
        if requestPermission && settings.searchContacts == true { contacts.requestPermission() }
        updateContactsControls()
    }
    func updateContactsControls() {
        contactsStatus?.stringValue = !contacts.enabled && contacts.permissionGranted ? "已授权 · 启用并保存后开始检索" : contacts.statusText
        contactsPermissionButton?.isEnabled = (!contacts.permissionGranted || contacts.enabled) && contacts.state != .loading
        contactsPermissionButton?.title = contacts.needsSystemSettings ? "前往系统设置…" : (contacts.permissionGranted ? "重新加载" : "授权访问…")
    }
    @objc func authorizeContacts() {
        if contacts.needsSystemSettings {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") { NSWorkspace.shared.open(url) }
        } else if contacts.permissionGranted {
            contacts.retry()
        } else {
            contacts.requestPermission { [weak self] in self?.updateContactsControls() }
        }
    }
    /// Return false to leave ordinary text copying entirely to the responder chain.
    @discardableResult func copyContactNumber(to board: NSPasteboard = .general) -> Bool {
        if let editor = input.currentEditor() as? NSTextView,
           editor.hasMarkedText() || editor.selectedRange().length > 0 { return false }
        let row = table.selectedRow
        guard !searching, !hiding, results.indices.contains(row), let phone = results[row].contact else { return false }
        contacts.refreshAuthorization()
        guard contacts.enabled, contacts.permissionGranted, settings.searchContacts == true else { return true }
        guard let number = phone.copyNumber else { status.stringValue = "特殊号码无法安全转成纯数字，请回车查看联系人"; return true }
        board.clearContents()
        if board.setString(number, forType: .string) { hideSearch() }
        else { status.stringValue = "复制失败，请重试" }
        return true
    }
    func syncScanMotion() {
        signature?.update(query: input.stringValue, scanning: indexing, animated: panel.isVisible && !hiding)
        let active = indexing && panel.isVisible && !hiding
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        scanMotion?.configure(style: currentMotionStyle, active: active && lastScan == nil, reduced: reduced)
        let busy = SearchStatusLayout.busy(indexing: indexing, searching: searching)
        scanIndicator?.configure(style: currentMotionStyle, active: busy && panel.isVisible && !hiding, reduced: reduced)
    }
    func updateStatus(total: Int? = nil) {
        defer { if fileSearchPending && !input.stringValue.isEmpty { status.stringValue += " · 文件仍在检索…" } }
        syncScanMotion()
        if settings.effectiveSearchMode == .lokii {
            status.stringValue = input.stringValue.isEmpty ? "Lokii 模式 · " + lokiiNote
                : "Lokii · 显示 \(results.count) 项 · " + lokiiNote
            if !lokiiQueryNote.isEmpty && !input.stringValue.isEmpty { status.stringValue += " · " + lokiiQueryNote }
            if shortcutError { status.stringValue += " · 快捷键冲突" }
            return
        }
        if indexing { status.stringValue = lastScan == nil ? "正在建立索引 · 当前结果可能不完整 · \(entries.count) 项" : "\(indexMode) · 暂用已有索引 · \(entries.count) 项"; return }
        let count = total ?? results.count
        let stamp = lastScan.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? "尚未扫描"
        let warning = scanErrors.isEmpty ? "" : " · \(scanErrors.count) 处无法读取，菜单可查看"
        let shortcut = shortcutError ? " · 快捷键冲突，请在设置更换" : ""
        status.stringValue = input.stringValue.isEmpty ? "已索引 \(entries.count) 项 · \(stamp) 更新\(warning)\(shortcut)" : "\(count) 个匹配 · 显示 \(results.count) 项 · 索引 \(entries.count) 项\(warning)\(shortcut)"
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { let view = HighlightRow(); view.style = settings.effectiveHighlightStyle; return view }
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row) else { return nil }
        let cell = CandidateCellView(frame: NSRect(x: 0, y: 0, width: searchWidth - 28, height: 60))
        let icon = NSImageView(frame: NSRect(x: 5, y: 6, width: 48, height: 48))
        let e = results[row]
        resultIcons.countLimit = 256
        let symbol = e.contact != nil ? "person.crop.circle" : (e.webURL == nil ? "gearshape" : "globe")
        let description = e.contact != nil ? "联系人" : (e.webURL == nil ? "系统设置" : "网页")
        let iconKey = (e.file.map { "\($0.modified):\($0.path)" } ?? symbol) as NSString
        if let cached = resultIcons.object(forKey: iconKey) { icon.image = cached }
        else {
            let image = e.file.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: symbol, accessibilityDescription: description)!
            resultIcons.setObject(image, forKey: iconKey); icon.image = image
        }
        let hintWidth: CGFloat = row < settings.effectiveVisibleRows || e.contact != nil ? 52 : 0
        let name = label(e.name, NSRect(x: 60, y: 6, width: searchWidth - 112 - hintWidth, height: 25), size: 18)
        let path = label(e.subtitle, NSRect(x: 60, y: 33, width: searchWidth - 112 - hintWidth, height: 20), size: 12, color: .secondaryLabelColor)
        name.font = searchFont(size: 18); path.font = searchFont(size: 12)
        cell.textField = name; cell.subtitleField = path; cell.imageView = icon
        cell.onContrastChange = { [weak cell] inverse in
            for case let badge as CandidateShortcutBadge in cell?.subviews ?? [] { badge.onBlue = inverse }
            for case let badge as PinnedStatusBadge in cell?.subviews ?? [] { badge.onBlue = inverse }
        }
        CandidateTextLayout.center(name: name, path: path, in: cell.bounds)
        name.autoresizingMask = [.width]; path.autoresizingMask = [.width]
        if e.isPinned {
            cell.addSubview(PinnedStatusBadge(frame: PinnedStatusBadge.place(after: name)))
        }
        cell.addSubview(name); cell.addSubview(path); cell.addSubview(icon)
        if hintWidth > 0 {
            let badge = CandidateShortcutBadge(frame: NSRect(x: cell.bounds.width - 56, y: (cell.bounds.height - 24) / 2, width: 44, height: 24))
            badge.number = row + 1; badge.restingLabel = e.contact?.copyNumber == nil ? nil : "⌘C"
            badge.showNumber = commandHeld && row < settings.effectiveVisibleRows; badge.available = !searching
            badge.isHidden = badge.restingLabel == nil && !badge.showNumber; badge.autoresizingMask = [.minXMargin, .minYMargin, .maxYMargin]
            badge.setAccessibilityElement(false)
            cell.addSubview(badge)
        }
        return cell
    }
    func moveSelection(_ delta: Int) {
        let count = numberOfRows(in: table); guard count > 0 else { return }
        let row = min(count - 1, max(0, table.selectedRow + delta)); table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table.scrollRowToVisible(row)
    }
    func updateCandidateShortcutHints() {
        guard let table else { return }
        for row in results.indices {
            guard let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) else { continue }
            for case let badge as CandidateShortcutBadge in cell.subviews {
                badge.showNumber = commandHeld && row < settings.effectiveVisibleRows
                badge.isHidden = badge.restingLabel == nil && !badge.showNumber; badge.available = !searching
            }
        }
    }
    @objc func openSelected() { openResult(at: table.selectedRow) }
    func openResult(at row: Int) {
        guard !searching, !hiding, results.indices.contains(row) else { return }
        // Capture the candidate now; never read a potentially changed selection later.
        let result = results[row]
        if case .setting(let destination) = result {
            openSettingsPage(destination.url); return
        }
        if result.contact != nil {
            contacts.refreshAuthorization()
            guard settings.searchContacts == true, contacts.enabled, contacts.permissionGranted else { return }
        }
        hideSearch { [weak self] in
            guard let self else { return }
            if let phone = result.contact {
                guard let url = phone.url, NSWorkspace.shared.open(url) else {
                    self.alert("无法打开联系人", "请打开系统通讯录查看。"); return
                }
                return
            }
            if let url = result.webURL {
                if !NSWorkspace.shared.open(url) { self.alert("无法打开网页", "请检查默认浏览器与网页地址。") }
                return
            }
            guard let entry = result.file else { return }
            let url = URL(fileURLWithPath: entry.path)
            guard FileManager.default.fileExists(atPath: url.path) else { self.alert("文件已移动或删除", "刷新索引后再试。"); self.reindex(); return }
            NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                DispatchQueue.main.async { if let error { self?.alert("无法打开", error.localizedDescription) } }
            }
        }
    }
    func showInfo() {
        let row = table.selectedRow
        guard !searching, !hiding, results.indices.contains(row) else { return }
        guard let path = results[row].file?.path else { status.stringValue = "此候选不是本地文件，无法显示文件简介"; return }
        hideSearch { [weak self] in
            guard let self else { return }
            guard FileManager.default.fileExists(atPath: path) else { self.alert("文件已移动或删除", "刷新索引后再试。"); self.reindex(); return }
            // Pass the path as an Apple-event argument, never interpolate it into script text.
            let source = """
            on showInfo(itemPath)
                set targetItem to POSIX file itemPath as alias
                tell application "Finder"
                    open information window of targetItem
                    activate
                end tell
            end showInfo
            """
            guard let script = NSAppleScript(source: source) else { return }
            let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            event.setParam(NSAppleEventDescriptor(string: "showinfo"), forKeyword: AEKeyword(keyASSubroutineName))
            let arguments = NSAppleEventDescriptor.list()
            arguments.insert(NSAppleEventDescriptor(string: path), at: 1)
            event.setParam(arguments, forKeyword: AEKeyword(keyDirectObject))
            var error: NSDictionary?
            script.executeAppleEvent(event, error: &error)
            if let error { self.alert("无法打开显示简介", "首次使用需要允许觅见控制 Finder。\n" + (error[NSAppleScript.errorMessage] as? String ?? "请在系统设置 → 隐私与安全性 → 自动化检查权限。")) }
        }
    }
    func reveal() {
        let row = table.selectedRow
        guard !searching, !hiding, results.indices.contains(row), let file = results[row].file else { return }
        let url = URL(fileURLWithPath: file.path)
        hideSearch { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    func copyPath() { let row = table.selectedRow; guard !searching, results.indices.contains(row), let address = results[row].file?.path ?? results[row].webURL?.absoluteString else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(address, forType: .string); status.stringValue = "已复制完整地址" }
    func alert(_ title: String, _ detail: String) { let a = NSAlert(); a.messageText = title; a.informativeText = detail; a.runModal() }
    @objc func showDiagnostics() {
        if settings.effectiveSearchMode == .lokii {
            openLokii()
            return
        }
        alert("名称索引状态", "共 \(entries.count) 项。\n仅读取名称、路径、类型和修改时间；不读取正文。\n不会递归跟随符号链接，不扫描应用包内部。\n" + (indexing ? "当前扫描：\(scanningPath)\n若停留，请检查 macOS 的文件夹访问授权弹窗。\n" : "") + (scanErrors.isEmpty ? "最近一次扫描未报告读取错误。" : scanErrors.joined(separator: "\n")))
    }
    func check(_ title: String, value: Bool, frame: NSRect, in view: NSView) -> NSButton {
        let b = SettingsCheckbox(title: title, target: nil, action: nil); b.frame = frame; b.state = value ? .on : .off; view.addSubview(b); return b
    }
    func popup(_ titles: [String], selected: Int, frame: NSRect, in view: NSView) -> NSPopUpButton {
        let p = NSPopUpButton(frame: frame, pullsDown: false); p.addItems(withTitles: titles); p.selectItem(at: max(0, min(titles.count - 1, selected))); view.addSubview(p); return p
    }
    func segments(_ titles: [String], selected: Int, frame: NSRect, in view: NSView) -> SettingsSegmentedControl {
        let control = SettingsSegmentedControl(labels: titles, selected: selected, frame: frame)
        view.addSubview(control); return control
    }
    @objc func previewThemeFont() {
        guard let root = settingsWindow?.contentView else { return }
        let family = fontPopup.titleOfSelectedItem ?? settings.effectiveFontName
        func apply(_ view: NSView) {
            if let control = view as? NSControl, let old = control.font {
                let bold = NSFontManager.shared.traits(of: old).contains(.boldFontMask)
                control.font = NSFontManager.shared.font(withFamily: family, traits: bold ? .boldFontMask : [], weight: bold ? 9 : 5, size: old.pointSize)
                    ?? NSFont(name: family, size: old.pointSize) ?? .systemFont(ofSize: old.pointSize)
            }
            if let text = view as? NSTextView {
                text.font = NSFont(name: family, size: text.font?.pointSize ?? 12)
                    ?? NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: text.font?.pointSize ?? 12)
            }
            for child in view.subviews { apply(child) }
        }
        apply(root)
        // NSTabView only attaches the selected page to its view hierarchy.
        for item in settingsTabs.tabViewItems { if let page = item.view { apply(page) } }
        stylePreview.fontName = family; stylePreview.needsDisplay = true
    }
    func editor(_ text: String, frame: NSRect, in view: NSView) -> NSTextView {
        let scroll = NSScrollView(frame: frame); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let t = NSTextView(frame: NSRect(x: 0, y: 0, width: frame.width - 20, height: frame.height)); t.isRichText = false; t.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        t.isAutomaticQuoteSubstitutionEnabled = false; t.isAutomaticDashSubstitutionEnabled = false; t.isAutomaticSpellingCorrectionEnabled = false
        t.isVerticallyResizable = true; t.autoresizingMask = [.width]; t.textContainer?.widthTracksTextView = true
        t.string = text; scroll.documentView = t; view.addSubview(scroll); return t
    }
    @objc func showSettings() {
        hideSearch(); NSApp.setActivationPolicy(.regular)
        if let settingsWindow { NSApp.activate(ignoringOtherApps: true); settingsWindow.deminiaturize(nil); settingsWindow.makeKeyAndOrderFront(nil); return }
        let height = min(CGFloat(700), (NSScreen.main?.visibleFrame.height ?? 920) - 100)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: height), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.delegate = self
        window.title = "觅见设置"; window.isReleasedWhenClosed = false; window.level = .normal
        let view = SettingsCanvas(frame: NSRect(x: 0, y: 0, width: 900, height: height)); window.contentView = view
        view.addSubview(label("Meet&See", NSRect(x: 20, y: 24, width: 130, height: 18), size: 10, color: .secondaryLabelColor))
        view.addSubview(label("觅见设置", NSRect(x: 20, y: 50, width: 132, height: 32), size: 20, bold: true))
        let tabs = NSTabView(frame: NSRect(x: 170, y: 24, width: 712, height: height - 88))
        tabs.tabViewType = .noTabsNoBorder; settingsTabs = tabs
        sidebarButtons.removeAll()
        for entry in SettingsNavigation.items {
            let item = SettingsSidebarButton(title: entry.title, target: self, action: #selector(changeSettingsTab(_:)))
            item.identifier = NSUserInterfaceItemIdentifier(entry.id)
            item.setButtonType(.radio); item.font = .systemFont(ofSize: 13)
            item.frame = NSRect(x: 16, y: entry.y, width: 136, height: 42)
            item.state = entry.id == "general" ? .on : .off
            sidebarButtons.append(item); view.addSubview(item)
        }
        let sideRule = NSBox(frame: NSRect(x: 158, y: 20, width: 1, height: height - 40))
        sideRule.boxType = .separator; view.addSubview(sideRule)
        view.addSubview(tabs)
        settingsDocument = TopView(frame: NSRect(x: 0, y: 0, width: 708, height: 900))
        let scopeContainer = TopView(frame: tabs.bounds)
        scopeContainer.autoresizingMask = [.width, .height]
        scopePage = SettingsPage(document: settingsDocument)
        scopePage.frame = NSRect(x: 0, y: 102, width: 712, height: tabs.bounds.height - 102)
        scopePage.autoresizingMask = [.width, .height]
        scopeContainer.addSubview(scopePage)
        scopePicker = segments(["白名单", "黑名单"], selected: 0, frame: NSRect(x: 150, y: 64, width: 400, height: 28), in: scopeContainer)
        scopePicker.target = self; scopePicker.action = #selector(changeScopeTab)
        selectedScope = 0; scopeOffsets = [0, 0]
        let scopeTab = NSTabViewItem(identifier: "scope"); scopeTab.label = "搜索范围"; scopeTab.view = scopeContainer; tabs.addTabViewItem(scopeTab)
        scopeContainer.addSubview(label("搜索范围", NSRect(x: 12, y: 0, width: 680, height: 28), size: 19, bold: true))
        legacyMigrationRequested = false
        scopeDescription = label("", NSRect(x: 12, y: 30, width: 530, height: 22), size: 12, color: .secondaryLabelColor)
        scopeContainer.addSubview(scopeDescription)
        migrationButton = button("采用当前分类", NSRect(x: 552, y: 26, width: 136, height: 28), #selector(adoptCurrentCategories), in: scopeContainer)
        migrationButton.isHidden = settings.legacyKinds == nil
        updateScopeDescription()
        whiteToggle = check("白名单 · 文件纳入范围", value: settings.usesWhitelist, frame: NSRect(x: 8, y: 64, width: 690, height: 30), in: settingsDocument)
        whiteToggle.target = self; whiteToggle.action = #selector(layoutSettingsSections)
        whiteBody = TopView(frame: NSRect(x: 0, y: 36, width: 708, height: 310)); settingsDocument.addSubview(whiteBody)
        whiteBody.addSubview(label("文件类型", NSRect(x: 12, y: 2, width: 100, height: 22), bold: true))
        allButton = check("所有文件类型", value: settings.allTypes, frame: NSRect(x: 150, y: 0, width: 220, height: 26), in: whiteBody)
        allButton.target = self; allButton.action = #selector(changeAllTypes)
        typeBody = TopView(frame: NSRect(x: 0, y: 34, width: 708, height: 148)); whiteBody.addSubview(typeBody)
        categoryButtons.removeAll(); typeSelectionChanged = false
        for (i, kind) in FileKind.displayed.enumerated() {
            categoryButtons[kind] = check(kind.label, value: settings.kinds.contains(kind), frame: NSRect(x: 150 + (i % 3) * 180, y: (i / 3) * 30, width: 170, height: 24), in: typeBody)
            categoryButtons[kind]?.toolTip = kind.examples
            categoryButtons[kind]?.setAccessibilityHelp(kind.examples)
            categoryButtons[kind]?.target = self; categoryButtons[kind]?.action = #selector(changeFileTypes)
        }
        typeBody.addSubview(label("额外扩展名", NSRect(x: 12, y: 102, width: 130, height: 22)))
        extensionField = NSTextField(frame: NSRect(x: 150, y: 98, width: 534, height: 26)); extensionField.placeholderString = "csv, xlsm, mp4"; extensionField.stringValue = settings.customExtensions; typeBody.addSubview(extensionField)
        typeBody.addSubview(label("额外扩展名会追加纳入，不会替代上方已选类型。", NSRect(x: 150, y: 126, width: 534, height: 20), size: 11, color: .secondaryLabelColor))
        whiteDetails = TopView(frame: NSRect(x: 0, y: 186, width: 708, height: 234)); whiteBody.addSubview(whiteDetails)
        extensionlessButton = check("包含无扩展名文件", value: settings.includeExtensionless == true, frame: NSRect(x: 150, y: 0, width: 260, height: 26), in: whiteDetails)
        extensionlessButton.target = self; extensionlessButton.action = #selector(updateExtensionlessHint)
        hiddenButton = check("包含隐藏文件", value: settings.showHidden, frame: NSRect(x: 430, y: 0, width: 254, height: 26), in: whiteDetails)
        extensionlessHint = label("", NSRect(x: 150, y: 32, width: 534, height: 22), size: 11, color: .secondaryLabelColor)
        whiteDetails.addSubview(extensionlessHint)
        scopeDirectoryLabel = label("文件目录", NSRect(x: 12, y: 70, width: 130, height: 22))
        whiteDetails.addSubview(scopeDirectoryLabel)
        scopeList = DirectoryListView(paths: settings.roots, frame: NSRect(x: 150, y: 66, width: 534, height: 200))
        scopeList.onHeightChange = { [weak self] in self?.layoutSettingsSections() }
        whiteDetails.addSubview(scopeList)
        addScopeButton = button("添加目录…", .zero, #selector(addScope), in: whiteDetails)
        scopeDirectoryHint = label("每行一个目录；类型与过滤条件仍同时生效。", .zero, size: 11, color: .secondaryLabelColor)
        whiteDetails.addSubview(scopeDirectoryHint)
        blackToggle = check("黑名单 · 排除条件", value: settings.usesBlacklist, frame: .zero, in: settingsDocument)
        blackToggle.target = self; blackToggle.action = #selector(layoutSettingsSections)
        scopeRule = NSBox(frame: .zero); scopeRule.boxType = .separator; settingsDocument.addSubview(scopeRule)
        blackBody = TopView(frame: NSRect(x: 0, y: 0, width: 708, height: 358)); settingsDocument.addSubview(blackBody)
        blackDirectoryLabel = label("排除目录", NSRect(x: 12, y: 4, width: 130, height: 22)); blackBody.addSubview(blackDirectoryLabel)
        excludedList = DirectoryListView(paths: settings.exclusions, frame: NSRect(x: 150, y: 0, width: 534, height: 30))
        excludedList.onHeightChange = { [weak self] in self?.layoutSettingsSections() }
        blackBody.addSubview(excludedList)
        addBlacklistScopeButton = button("添加目录…", .zero, #selector(addBlacklistScope), in: blackBody)
        blackDirectoryHint = label("命中的目录及其全部子项都会排除。", .zero, size: 11, color: .secondaryLabelColor); blackBody.addSubview(blackDirectoryHint)
        blockedExtensionLabel = label("排除扩展名", NSRect(x: 12, y: 124, width: 130, height: 22)); blackBody.addSubview(blockedExtensionLabel)
        blockedExtensionField = NSTextField(frame: NSRect(x: 150, y: 120, width: 534, height: 26)); blockedExtensionField.placeholderString = "例如 tmp, log；逗号或空格分隔"; blockedExtensionField.stringValue = settings.blockedExtensions ?? ""; blackBody.addSubview(blockedExtensionField)
        blockedKeywordLabel = label("排除关键词", NSRect(x: 12, y: 164, width: 130, height: 22)); blackBody.addSubview(blockedKeywordLabel)
        blockedKeywordEditor = editor((settings.blockedKeywords ?? []).joined(separator: "\n"), frame: NSRect(x: 150, y: 160, width: 534, height: 70), in: blackBody)
        blockedKeywordHint = label("每行一个；名称包含任意关键词即排除，忽略大小写及全半角。", NSRect(x: 150, y: 240, width: 534, height: 22), size: 11, color: .secondaryLabelColor); blackBody.addSubview(blockedKeywordHint)
        linkTypeLabel = label("链接类型", NSRect(x: 12, y: 282, width: 130, height: 22)); blackBody.addSubview(linkTypeLabel)
        aliasExclusionButton = check("排除 Finder 替身", value: settings.excludeFinderAliases == true, frame: NSRect(x: 150, y: 278, width: 232, height: 26), in: blackBody)
        symlinkExclusionButton = check("排除符号链接（谨慎开启）", value: settings.excludeSymbolicLinks == true, frame: NSRect(x: 394, y: 278, width: 290, height: 26), in: blackBody)
        linkTypeHint = label("开启会隐藏 Safari 等符号链接入口；不会影响目标原文件。", NSRect(x: 150, y: 316, width: 534, height: 22), size: 11, color: .secondaryLabelColor); blackBody.addSubview(linkTypeHint)
        contactsSection = TopView(frame: NSRect(x: 0, y: 0, width: 708, height: 280))
        settingsDocument.addSubview(contactsSection)
        let contactsRule = NSBox(frame: NSRect(x: 12, y: 0, width: 680, height: 1))
        contactsRule.boxType = .separator; contactsSection.addSubview(contactsRule)
        contactsSection.addSubview(label("其他来源", NSRect(x: 12, y: 24, width: 110, height: 22), bold: true))
        contactsButton = check("检索通讯录", value: settings.searchContacts == true, frame: NSRect(x: 150, y: 22, width: 350, height: 26), in: contactsSection)
        contactsSection.addSubview(label("仅完整姓名或完整拼音命中；不匹配缩写、部分姓名和号码。", NSRect(x: 150, y: 60, width: 534, height: 22), size: 11, color: .secondaryLabelColor))
        contactsSection.addSubview(label("⌘C 复制纯数字主号，去除明确的 +86／0086 大陆国家码。", NSRect(x: 150, y: 90, width: 534, height: 22), size: 11, color: .secondaryLabelColor))
        contactsStatus = label("", NSRect(x: 150, y: 130, width: 534, height: 22), size: 11, color: .secondaryLabelColor)
        contactsSection.addSubview(contactsStatus)
        contactsPermissionButton = button("授权访问…", NSRect(x: 150, y: 168, width: 154, height: 28), #selector(authorizeContacts), in: contactsSection)
        contactsSection.addSubview(label("独立开关控制；保存后申请权限，不受文件类型或目录限制。", NSRect(x: 150, y: 212, width: 534, height: 22), size: 11, color: .secondaryLabelColor))
        updateContactsControls()
        contactsSection.addSubview(label("仅本机内存检索，不写入磁盘缓存，不交给 Lokii。", NSRect(x: 150, y: 240, width: 534, height: 22), size: 11, color: .secondaryLabelColor))
        generalBody = TopView(frame: NSRect(x: 0, y: 0, width: 708, height: 64)); settingsDocument.addSubview(generalBody)
        generalBody.addSubview(label("白名单关闭：仅扫描 ~/，不限制类型；黑名单关闭：保留规则但不生效。", NSRect(x: 12, y: 0, width: 680, height: 22), size: 11, color: .secondaryLabelColor))
        generalBody.addSubview(label("隐藏文件偏好在白名单关闭后仍生效；如需调整，请展开白名单。", NSRect(x: 12, y: 28, width: 680, height: 22), size: 11, color: .secondaryLabelColor))
        let generalPage = TopView(frame: NSRect(x: 0, y: 0, width: 708, height: 698))
        generalPage.addSubview(label("通用", NSRect(x: 12, y: 12, width: 680, height: 32), size: 19, bold: true))
        generalPage.addSubview(BrandAboutView(frame: NSRect(x: 134, y: 58, width: 440, height: 186)))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let versionLabel = label("Meet&See  ·  \(version)  ·  本地名称搜索与快速打开", NSRect(x: 12, y: 250, width: 680, height: 22), size: 11, color: .secondaryLabelColor)
        versionLabel.alignment = .center; generalPage.addSubview(versionLabel)
        let brandRule = NSBox(frame: NSRect(x: 12, y: 286, width: 680, height: 1)); brandRule.boxType = .separator; generalPage.addSubview(brandRule)
        generalPage.addSubview(label("启动与系统", NSRect(x: 12, y: 304, width: 680, height: 26), size: 15, bold: true))
        loginButton = check("登录时自动启动觅见", value: false, frame: NSRect(x: 12, y: 344, width: 500, height: 26), in: generalPage)
        loginButton.target = self; loginButton.action = #selector(toggleLoginItem)
        loginStatusLabel = label("", NSRect(x: 12, y: 378, width: 680, height: 24), size: 12, color: .secondaryLabelColor); generalPage.addSubview(loginStatusLabel)
        _ = button("在系统设置中管理…", NSRect(x: 12, y: 414, width: 188, height: 30), #selector(openLoginItems), in: generalPage)
        generalPage.addSubview(label("此页由 macOS 管理，修改立即生效，无需保存。", NSRect(x: 12, y: 460, width: 680, height: 22), size: 11, color: .secondaryLabelColor))
        let permissionRule = NSBox(frame: NSRect(x: 12, y: 498, width: 680, height: 1)); permissionRule.boxType = .separator; generalPage.addSubview(permissionRule)
        generalPage.addSubview(label("权限 · 完全磁盘访问权限", NSRect(x: 12, y: 518, width: 680, height: 26), size: 15, bold: true))
        generalPage.addSubview(label("访问已选范围内受保护的位置；授权不会扩大搜索范围。", NSRect(x: 12, y: 554, width: 680, height: 24), size: 12, color: .secondaryLabelColor))
        _ = button("前往系统设置授权…", NSRect(x: 12, y: 592, width: 190, height: 30), #selector(openDiskAccess), in: generalPage)
        _ = button("在 Finder 中显示觅见", NSRect(x: 218, y: 592, width: 190, height: 30), #selector(revealApplication), in: generalPage)
        generalPage.addSubview(label("请在系统页面添加并开启觅见；权限状态以系统设置为准。", NSRect(x: 12, y: 636, width: 680, height: 22), size: 11, color: .secondaryLabelColor))
        generalPage.addSubview(label("授权后可手动刷新索引；若系统要求重启，请自行确认。", NSRect(x: 12, y: 664, width: 680, height: 22), size: 11, color: .secondaryLabelColor))
        let searchPage = TopView(frame: NSRect(x: 0, y: 0, width: 708, height: 646))
        searchPage.addSubview(label("搜索行为", NSRect(x: 12, y: 12, width: 680, height: 32), size: 19, bold: true))
        searchPage.addSubview(label("搜索范围决定纳入哪些文件；这里决定如何检索和更新结果。", NSRect(x: 12, y: 52, width: 680, height: 22), size: 12, color: .secondaryLabelColor))
        searchPage.addSubview(label("匹配方式", NSRect(x: 12, y: 112, width: 110, height: 22), bold: true))
        matchPopup = segments(["仅名称", "名称与完整路径"], selected: settings.matchPath ? 1 : 0, frame: NSRect(x: 150, y: 108, width: 280, height: 28), in: searchPage)
        searchPage.addSubview(label("路径匹配包含父文件夹名称；两者都不读取文件正文。", NSRect(x: 150, y: 148, width: 530, height: 22), size: 11, color: .secondaryLabelColor))
        searchPage.addSubview(label("结果排序", NSRect(x: 12, y: 202, width: 110, height: 22), bold: true))
        sortPopup = segments(["名称排序", "修改时间优先"], selected: settings.sortModified ? 1 : 0, frame: NSRect(x: 150, y: 198, width: 280, height: 28), in: searchPage)
        searchPage.addSubview(label("完整名称、前缀等匹配优先级不变；此选项决定同级结果顺序。", NSRect(x: 150, y: 238, width: 540, height: 22), size: 11, color: .secondaryLabelColor))
        applicationsFirstButton = check("应用程序优先", value: settings.applicationsFirst == true, frame: NSRect(x: 150, y: 274, width: 500, height: 26), in: searchPage)
        searchPage.addSubview(label("匹配的应用程序优先显示，但不超过常用置顶目标。", NSRect(x: 150, y: 310, width: 540, height: 22), size: 11, color: .secondaryLabelColor))
        searchPage.addSubview(label("候选数量上限", NSRect(x: 12, y: 358, width: 130, height: 22), bold: true))
        limitPopup = segments(["5", "10", "20", "30", "50"], selected: Settings.candidateLimits.firstIndex(of: settings.effectiveCandidateLimit) ?? 2, frame: NSRect(x: 150, y: 354, width: 400, height: 28), in: searchPage)
        searchPage.addSubview(label("最多返回的候选总数；窗口一次可见几行由外观设置决定。", NSRect(x: 150, y: 392, width: 530, height: 22), size: 11, color: .secondaryLabelColor))
        searchPage.addSubview(label("索引更新", NSRect(x: 12, y: 448, width: 110, height: 22), bold: true))
        refreshButton = check("自动监听文件变化", value: settings.autoRefresh, frame: NSRect(x: 150, y: 444, width: 500, height: 26), in: searchPage)
        searchPage.addSubview(label("合并变化后增量更新，重启追赶历史；原生模式另有每日校准。", NSRect(x: 150, y: 484, width: 540, height: 22), size: 11, color: .secondaryLabelColor))
        searchPage.addSubview(label("事件丢失或监听不可用时回退全量校准；⌘R 可随时手动刷新。", NSRect(x: 150, y: 514, width: 540, height: 22), size: 11, color: .secondaryLabelColor))
        systemSettingsButton = check("搜索系统设置（一、二级页面）", value: settings.searchSystemSettings != false, frame: NSRect(x: 150, y: 558, width: 500, height: 26), in: searchPage)
        searchPage.addSubview(label("独立于文件范围与过滤规则；关闭不重建文件索引。", NSRect(x: 150, y: 596, width: 534, height: 22), size: 11, color: .secondaryLabelColor))
        for child in searchPage.subviews where child.frame.minY >= 100 {
            child.setFrameOrigin(NSPoint(x: child.frame.minX, y: child.frame.minY + 252))
        }
        searchPage.setFrameSize(NSSize(width: 708, height: 898))
        searchPage.addSubview(label("检索来源", NSRect(x: 12, y: 810, width: 110, height: 22), bold: true))

        searchPage.addSubview(label("检索模式", NSRect(x: 12, y: 112, width: 110, height: 22), bold: true))
        modePicker = segments(["原生", "Lokii"], selected: settings.effectiveSearchMode == .lokii ? 1 : 0,
            frame: NSRect(x: 150, y: 108, width: 280, height: 28), in: searchPage)
        modePicker.target = self; modePicker.action = #selector(changeSearchMode)
        modeHint = label("", NSRect(x: 150, y: 148, width: 534, height: 22), size: 11, color: .secondaryLabelColor)
        searchPage.addSubview(modeHint)
        lokiiDetails = label("", NSRect(x: 150, y: 182, width: 534, height: 22), size: 11, color: .secondaryLabelColor)
        searchPage.addSubview(lokiiDetails)
        lokiiCheckButton = button("检查引擎", NSRect(x: 150, y: 218, width: 112, height: 28), #selector(checkLokiiConnection), in: searchPage)
        _ = button("引擎详情", NSRect(x: 274, y: 218, width: 112, height: 28), #selector(openLokii), in: searchPage)
        searchPage.addSubview(label("使用觅见已保存范围及私有缓存；不读取或改写官方 Lokii 配置。", NSRect(x: 150, y: 262, width: 534, height: 22), size: 11, color: .secondaryLabelColor))
        searchPage.addSubview(label("同步预取上限为5000项；类型等条件由觅见过滤，限量结果非完整总数。", NSRect(x: 150, y: 292, width: 534, height: 22), size: 11, color: .secondaryLabelColor))
        changeSearchMode()
        let interactionPage = TopView(frame: NSRect(x: 0, y: 0, width: 708, height: 446))
        interactionPage.addSubview(label("交互", NSRect(x: 12, y: 12, width: 680, height: 32), size: 19, bold: true))
        interactionPage.addSubview(label("熟悉的快捷键，让操作留在指尖。", NSRect(x: 12, y: 52, width: 680, height: 22), size: 12, color: .secondaryLabelColor))
        interactionPage.addSubview(label("唤出 / 收起", NSRect(x: 12, y: 110, width: 110, height: 22)))
        hotPopup = popup(["⌃⌥Space", "⌃⇧Space", "不注册快捷键", "⌘Space（默认）"], selected: settings.hotKey, frame: NSRect(x: 150, y: 106, width: 260, height: 28), in: interactionPage)
        interactionPage.addSubview(label("其他快捷键", NSRect(x: 12, y: 174, width: 130, height: 22), bold: true))
        let shortcuts = [("↑ ↓", "选择候选项"), ("↵", "使用默认应用打开"),
                         ("⌘1–⌘N", "打开前 N 项；N 为可见行数，滚动不重新编号"),
                         ("⌘ ↵", "在 Finder 中定位"), ("⌘ I", "打开原生简介"),
                         ("⌘ C", "联系人：复制纯数字主号；选中文字时仍复制文字"), ("Esc", "收起搜索面板")]
        for (i, shortcut) in shortcuts.enumerated() {
            let tag = ContinuousKeycapBox(frame: NSRect(x: 150, y: 170 + i * 34, width: 88, height: 26))
            tag.boxType = .custom; tag.titlePosition = .noTitle
            tag.borderWidth = 0.5; tag.cornerRadius = 6
            tag.fillColor = .quaternaryLabelColor; tag.borderColor = .separatorColor
            tag.contentViewMargins = .zero
            interactionPage.addSubview(tag)
            let keys = label(shortcut.0, .zero, size: 13)
            keys.alignment = .left; keys.translatesAutoresizingMaskIntoConstraints = false
            tag.contentView!.addSubview(keys)
            let description = label(shortcut.1, .zero, size: 13, color: .secondaryLabelColor)
            description.alignment = .left; description.translatesAutoresizingMaskIntoConstraints = false
            interactionPage.addSubview(description)
            NSLayoutConstraint.activate([
                keys.leadingAnchor.constraint(equalTo: tag.contentView!.leadingAnchor, constant: 10),
                keys.centerYAnchor.constraint(equalTo: tag.contentView!.centerYAnchor),
                keys.trailingAnchor.constraint(lessThanOrEqualTo: tag.contentView!.trailingAnchor, constant: -8),
                description.leadingAnchor.constraint(equalTo: interactionPage.leadingAnchor, constant: 254),
                description.centerYAnchor.constraint(equalTo: tag.centerYAnchor),
                description.trailingAnchor.constraint(lessThanOrEqualTo: interactionPage.trailingAnchor, constant: -24)
            ])
        }
        let appearancePage = TopView(frame: NSRect(x: 0, y: 0, width: 708, height: 622))
        appearancePage.addSubview(label("外观", NSRect(x: 12, y: 12, width: 680, height: 28), size: 19, bold: true))
        appearancePage.addSubview(label("候选主题", NSRect(x: 12, y: 54, width: 680, height: 24), size: 15, bold: true))
        draftStyle = settings.effectiveHighlightStyle
        stylePreview = StylePreview(frame: NSRect(x: 64, y: 90, width: 400, height: 178)); stylePreview.style = draftStyle
        stylePreview.glassTintStrength = CGFloat(settings.effectiveGlassTintStrength)
        stylePreview.setAccessibilityElement(true); stylePreview.setAccessibilityRole(.image); stylePreview.setAccessibilityLabel(draftStyle.title + "预览")
        appearancePage.addSubview(stylePreview)
        themeButtons = HighlightStyle.selectable.enumerated().map { index, style in
            let choice = ThemeChoiceButton(style: style, frame: NSRect(x: 484, y: 95 + CGFloat(index) * 44, width: 144, height: 36))
            choice.state = style == draftStyle ? .on : .off
            choice.target = self; choice.action = #selector(selectHighlight(_:))
            appearancePage.addSubview(choice)
            return choice
        }
        let materialRule = NSBox(frame: NSRect(x: 12, y: 288, width: 680, height: 1)); materialRule.boxType = .separator; appearancePage.addSubview(materialRule)
        appearancePage.addSubview(label("字体与玻璃", NSRect(x: 12, y: 304, width: 680, height: 26), size: 15, bold: true))
        appearancePage.addSubview(label("主题字体", NSRect(x: 12, y: 346, width: 130, height: 22)))
        let fonts = NSFontManager.shared.availableFontFamilies.sorted()
        fontPopup = popup(fonts, selected: fonts.firstIndex(of: settings.effectiveFontName) ?? 0, frame: NSRect(x: 150, y: 342, width: 280, height: 28), in: appearancePage)
        fontPopup.target = self; fontPopup.action = #selector(previewThemeFont)
        appearancePage.addSubview(label("玻璃染色强度", NSRect(x: 12, y: 386, width: 130, height: 24)))
        opacitySlider = NSSlider(value: settings.effectiveGlassTintStrength, minValue: 0, maxValue: 1, target: self, action: #selector(previewOpacity))
        opacitySlider.frame = NSRect(x: 150, y: 382, width: 430, height: 30)
        opacitySlider.numberOfTickMarks = 11; opacitySlider.allowsTickMarkValuesOnly = true; opacitySlider.isContinuous = true
        opacitySlider.setAccessibilityLabel("玻璃染色强度")
        appearancePage.addSubview(opacitySlider)
        opacityValue = label(String(format: "%.1f", settings.effectiveGlassTintStrength), NSRect(x: 600, y: 386, width: 70, height: 24))
        appearancePage.addSubview(opacityValue)
        appearancePage.addSubview(label("拖动即预览真实面板；取消或关闭设置后恢复已保存值。", NSRect(x: 150, y: 424, width: 534, height: 22), size: 11, color: .secondaryLabelColor))
        if #unavailable(macOS 26.0) {
            opacitySlider.isEnabled = false
            opacityValue.stringValue = "需26+"
        }
        let divider = NSBox(frame: NSRect(x: 12, y: 460, width: 680, height: 1)); divider.boxType = .separator; appearancePage.addSubview(divider)
        appearancePage.addSubview(label("窗口尺寸", NSRect(x: 12, y: 476, width: 680, height: 26), size: 15, bold: true))
        appearancePage.addSubview(label("宽度", NSRect(x: 12, y: 516, width: 130, height: 22)))
        widthPicker = segments(["窄", "中", "宽"], selected: ["narrow", "medium", "wide"].firstIndex(of: settings.windowWidth ?? "medium") ?? 1, frame: NSRect(x: 150, y: 512, width: 220, height: 28), in: appearancePage)
        appearancePage.addSubview(label("可见行数", NSRect(x: 12, y: 554, width: 130, height: 22)))
        rowsPicker = segments(["3", "4", "5", "6", "7", "8"], selected: settings.effectiveVisibleRows - 3, frame: NSRect(x: 150, y: 550, width: 250, height: 28), in: appearancePage)
        appearancePage.addSubview(label("候选不足时收缩，超出后滚动；保存后应用。", NSRect(x: 150, y: 588, width: 534, height: 22), size: 11, color: .secondaryLabelColor))
        for (id, title, page) in [("general", "通用", generalPage), ("search", "搜索行为", searchPage), ("interaction", "交互", interactionPage), ("appearance", "外观", appearancePage)] {
            let scroller = SettingsPage(document: page)
            let item = NSTabViewItem(identifier: id); item.label = title; item.view = scroller
            if id == "general" { tabs.insertTabViewItem(item, at: 0) } else { tabs.addTabViewItem(item) }
        }
        let pinsTab = NSTabViewItem(identifier: "pins"); pinsTab.label = "常用置顶"; pinsTab.view = makePinsPage(); tabs.addTabViewItem(pinsTab)
        let diagnosisPage = TopView(frame: NSRect(x: 0, y: 0, width: 708, height: 526))
        diagnosisPage.addSubview(label("检索诊断", NSRect(x: 12, y: 12, width: 680, height: 32), size: 19, bold: true))
        diagnosisPage.addSubview(label("为什么没搜到？只读检查，不修改规则或扩大权限。", NSRect(x: 12, y: 54, width: 680, height: 22), size: 12, color: .secondaryLabelColor))
        diagnosticPath = NSTextField(frame: NSRect(x: 12, y: 98, width: 520, height: 28)); diagnosticPath.placeholderString = "文件或文件夹完整路径（支持 ~/）"
        diagnosisPage.addSubview(diagnosticPath)
        _ = button("选择对象…", NSRect(x: 550, y: 98, width: 130, height: 28), #selector(chooseDiagnosticItem), in: diagnosisPage)
        diagnosticQuery = NSTextField(frame: NSRect(x: 12, y: 142, width: 520, height: 28)); diagnosticQuery.placeholderString = "当时输入的关键词（可选）"
        diagnosisPage.addSubview(diagnosticQuery)
        _ = button("开始诊断", NSRect(x: 550, y: 142, width: 130, height: 28), #selector(runDiagnostic), in: diagnosisPage)
        diagnosisPage.addSubview(label("使用已保存的规则；其他页面的未保存修改不参与本次诊断。", NSRect(x: 12, y: 186, width: 680, height: 22), size: 11, color: .secondaryLabelColor))
        diagnosticOutput = editor("选择对象或填写路径后开始。", frame: NSRect(x: 12, y: 224, width: 680, height: 286), in: diagnosisPage)
        diagnosticOutput.isEditable = false
        let diagnosisTab = NSTabViewItem(identifier: "diagnostics"); diagnosisTab.view = SettingsPage(document: diagnosisPage)
        tabs.addTabViewItem(diagnosisTab)
        settingsCancelButton = button("取消", NSRect(x: 640, y: height - 48, width: 90, height: 30), #selector(cancelSettings), in: view)
        settingsSaveButton = button("保存", NSRect(x: 744, y: height - 48, width: 124, height: 30), #selector(saveSettings), in: view)
        tabs.selectTabViewItem(at: 0)
        updateSettingsActions()
        settingsWindow = window; layoutSettingsSections(); previewThemeFont(); refreshLoginStatus()
        window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func refreshLoginStatus() {
        guard loginButton != nil else { return }
        switch SMAppService.mainApp.status {
        case .enabled:
            loginButton.state = .on; loginStatusLabel.stringValue = "已开启 · macOS 将在你登录账户时启动觅见。"
        case .requiresApproval:
            loginButton.state = .on; loginStatusLabel.stringValue = "等待系统批准 · 请在系统设置的登录项中允许觅见。"
        case .notRegistered:
            loginButton.state = .off; loginStatusLabel.stringValue = "未开启 · 仅在你手动打开时运行。"
        case .notFound:
            loginButton.state = .off; loginStatusLabel.stringValue = "系统未找到登录项服务，请确认应用位置与签名。"
        @unknown default:
            loginButton.state = .off; loginStatusLabel.stringValue = "无法识别系统状态，请在系统设置中检查。"
        }
    }
    @objc func toggleLoginItem() {
        let enable = loginButton.state == .on
        let current = SMAppService.mainApp.status
        do {
            if enable {
                if current != .enabled && current != .requiresApproval { try SMAppService.mainApp.register() }
            } else if current == .enabled || current == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            alert("无法更改登录启动", error.localizedDescription)
        }
        refreshLoginStatus()
    }
    func openSettingsPage(_ url: URL) {
        hideSearch { [weak self] in
            if !NSWorkspace.shared.open(url) {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                self?.alert("未能直达设置页面", "请在系统设置中手动选择对应项目。完全磁盘访问权限位于隐私与安全性中。")
            }
        }
    }
    @objc func chooseDiagnosticItem() {
        let picker = NSOpenPanel(); picker.canChooseFiles = true; picker.canChooseDirectories = true
        if picker.runModal() == .OK, let url = picker.url { diagnosticPath.stringValue = url.path }
    }
    @objc func runDiagnostic() {
        let raw = diagnosticPath.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix("/") || raw.hasPrefix("~/") else { diagnosticOutput.string = "请填写绝对路径或 ~/ 开头的路径。"; return }
        let path = (raw as NSString).expandingTildeInPath, query = diagnosticQuery.stringValue
        let snapshot = settings, index = entries, busy = indexing, errors = scanErrors
        diagnosticGeneration += 1; let generation = diagnosticGeneration
        diagnosticOutput.string = "正在检查…"
        diagnosticQueue.async { [weak self] in
            var report = diagnoseFile(path: path, query: query, settings: snapshot, entries: index, indexing: busy, errors: errors)
            if snapshot.effectiveSearchMode == .lokii {
                let term = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? URL(fileURLWithPath: path).lastPathComponent : query
                let start = ProcessInfo.processInfo.systemUptime
                do {
                    guard let self else { return }
                    let response = try LokiiEngine(process: self.lokiiProcess).searchFiles(query: term, settings: snapshot)
                    let state = self.lokiiProcess.snapshot
                    report += "\n\n内置引擎状态：\(state["phase"] as? String ?? "未知") · \(state["count"] as? Int ?? 0) 项"
                    let exact = try self.lokiiProcess.request("inspect", fields: ["path": path])
                    report += exact["present"] as? Bool == true ? "\n核心索引包含此对象。" : "\n当前核心索引未包含此对象；请结合阶段和权限判断。"
                    let present = response.source.contains { $0.path == path }
                    let visible = response.files.entries.contains { $0.path == path }
                    report += "\n\nLokii 请求：\(Int((ProcessInfo.processInfo.systemUptime - start) * 1000))ms · 实际适配 \(response.source.count) 项。"
                    report += present ? (visible ? "\n目标在本次文件候选内（常用置顶和系统设置还可能占用最终名额）。" : "\n本次来源含目标，但未进入文件候选：请核对匹配、过滤和数量上限。")
                        : "\n本次限量返回未包含目标，不能断言它未被索引或不存在。"
                    report += "\n" + response.note
                } catch { report += "\n\nLokii 请求失败：" + error.localizedDescription }
            }
            DispatchQueue.main.async {
                guard let self, self.settingsWindow != nil, self.diagnosticGeneration == generation else { return }
                self.diagnosticOutput.string = report
            }
        }
    }
    @objc func openDiskAccess() {
        openSettingsPage(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
    @objc func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
    @objc func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
    func applicationDidBecomeActive(_ notification: Notification) {
        contacts.refreshAuthorization(); updateContactsControls()
        if settingsWindow != nil { refreshLoginStatus() }
    }
    func updateSettingsActions() {
        let immediate = ["general", "diagnostics"].contains(settingsTabs.selectedTabViewItem?.identifier as? String ?? "")
        settingsSaveButton.isHidden = immediate
        settingsCancelButton.isHidden = immediate
        settingsCancelButton.isEnabled = !savingMode
        settingsSaveButton.isEnabled = !immediate && !savingMode
        settingsSaveButton.keyEquivalent = immediate ? "" : "\r"
    }
    @objc func changeSettingsTab(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, settingsTabs.tabViewItems.contains(where: { ($0.identifier as? String) == id }) else { return }
        refreshLoginStatus()
        sidebarButtons.forEach { $0.state = $0 === sender ? .on : .off; $0.needsDisplay = true }
        settingsTabs.selectTabViewItem(withIdentifier: id)
        updateSettingsActions()
    }
    func applyGlassTint(_ strength: Double) {
        if #available(macOS 26.0, *), let glass = glassSurface as? NSGlassEffectView {
            glass.tintColor = strength == 0 ? nil : NSColor.white.withAlphaComponent(strength)
        }
    }
    @objc func changeAllTypes() {
        typeSelectionChanged = true
        if settings.legacyKinds != nil {
            legacyMigrationRequested = true
            migrationButton.title = "新分类待保存"
            migrationButton.isEnabled = false
            updateScopeDescription()
        }
        layoutSettingsSections()
    }
    @objc func updateExtensionlessHint() {
        guard extensionlessHint != nil else { return }
        extensionlessHint.stringValue = allButton.state == .on
            ? "所有文件类型已纳入；此项自动包含无扩展名文件。隐藏文件仍由右侧开关控制。"
            : (extensionlessButton.state == .on
                ? "已单独纳入无扩展名文件；隐藏文件仍由右侧开关控制。"
                : "未纳入无扩展名文件；隐藏文件仍由右侧开关控制。")
    }
    func updateScopeDescription() {
        guard scopeDescription != nil else { return }
        if settings.legacyKinds != nil && !legacyMigrationRequested {
            scopeDescription.stringValue = "旧分类仍在兼容模式；调整类型或点击右侧按钮后，当前勾选将作为新规则。"
        } else if settings.legacyKinds != nil {
            scopeDescription.stringValue = "新分类规则待保存；当前勾选将在保存后生效。"
        } else {
            scopeDescription.stringValue = "白名单掌管纳入范围；黑名单掌管排除条件。悬停类型可查看格式。"
        }
    }
    @objc func adoptCurrentCategories() {
        legacyMigrationRequested = true
        migrationButton.title = "新分类待保存"
        migrationButton.isEnabled = false
        updateScopeDescription()
    }
    @objc func changeFileTypes() {
        typeSelectionChanged = true
        if settings.legacyKinds != nil { legacyMigrationRequested = true; migrationButton.title = "新分类待保存"; migrationButton.isEnabled = false; updateScopeDescription() }
    }
    @objc func previewOpacity() {
        let value = (opacitySlider.doubleValue * 10).rounded() / 10
        opacitySlider.doubleValue = value
        opacityValue.stringValue = String(format: "%.1f", value)
        stylePreview?.glassTintStrength = CGFloat(value)
        applyGlassTint(value)
    }
    @objc func selectHighlight(_ sender: ThemeChoiceButton) {
        draftStyle = sender.style
        for button in themeButtons {
            button.state = button === sender ? .on : .off
            button.needsDisplay = true
        }
        stylePreview.style = draftStyle; stylePreview.needsDisplay = true
        stylePreview.setAccessibilityLabel(draftStyle.title + "预览")
    }
    @objc func layoutSettingsSections() {
        typeBody.isHidden = allButton.state == .on
        extensionlessButton.isEnabled = allButton.state != .on
        updateExtensionlessHint()
        let scopeRowsHeight = scopeList.preferredHeight
        scopeDirectoryLabel.frame = NSRect(x: 12, y: 70, width: 130, height: 22)
        scopeList.frame = NSRect(x: 150, y: 66, width: 534, height: scopeRowsHeight)
        addScopeButton.frame = NSRect(x: 150, y: 74 + scopeRowsHeight, width: 112, height: 28)
        scopeDirectoryHint.frame = NSRect(x: 270, y: 79 + scopeRowsHeight, width: 414, height: 20)
        let scopeDetailsHeight = scopeRowsHeight + 112
        whiteDetails.setFrameSize(NSSize(width: 708, height: scopeDetailsHeight))
        let detailY: CGFloat = typeBody.isHidden ? 34 : 182
        whiteDetails.setFrameOrigin(NSPoint(x: 0, y: detailY))
        whiteBody.setFrameSize(NSSize(width: 708, height: detailY + scopeDetailsHeight))

        let white = scopePicker.selectedSegment == 0
        whiteToggle.isHidden = !white; blackToggle.isHidden = white
        whiteToggle.frame = NSRect(x: 8, y: 0, width: 690, height: 30)
        blackToggle.frame = whiteToggle.frame
        whiteBody.isHidden = !white || whiteToggle.state != .on
        blackBody.isHidden = white || blackToggle.state != .on
        scopeRule.isHidden = true
        scopePicker.setLabel("白名单 · " + (whiteToggle.state == .on ? "已启用" : "未启用"), forSegment: 0)
        scopePicker.setLabel("黑名单 · " + (blackToggle.state == .on ? "已启用" : "未启用"), forSegment: 1)
        var y: CGFloat = 40
        if !whiteBody.isHidden { whiteBody.setFrameOrigin(NSPoint(x: 0, y: y)); y += whiteBody.frame.height }
        let excludedRowsHeight = excludedList.preferredHeight
        excludedList.frame = NSRect(x: 150, y: 0, width: 534, height: excludedRowsHeight)
        addBlacklistScopeButton.frame = NSRect(x: 150, y: excludedRowsHeight + 8, width: 112, height: 28)
        blackDirectoryHint.frame = NSRect(x: 270, y: excludedRowsHeight + 13, width: 414, height: 20)
        blockedExtensionLabel.frame = NSRect(x: 12, y: excludedRowsHeight + 50, width: 130, height: 22)
        blockedExtensionField.frame = NSRect(x: 150, y: excludedRowsHeight + 46, width: 534, height: 26)
        blockedKeywordLabel.frame = NSRect(x: 12, y: excludedRowsHeight + 90, width: 130, height: 22)
        if let scroll = blockedKeywordEditor.enclosingScrollView {
            scroll.frame = NSRect(x: 150, y: excludedRowsHeight + 86, width: 534, height: 70)
            blockedKeywordEditor.frame = NSRect(x: 0, y: 0, width: 514, height: 70)
        }
        blockedKeywordHint.frame = NSRect(x: 150, y: excludedRowsHeight + 166, width: 534, height: 22)
        linkTypeLabel.frame = NSRect(x: 12, y: excludedRowsHeight + 208, width: 130, height: 22)
        aliasExclusionButton.frame = NSRect(x: 150, y: excludedRowsHeight + 204, width: 232, height: 26)
        symlinkExclusionButton.frame = NSRect(x: 394, y: excludedRowsHeight + 204, width: 290, height: 26)
        linkTypeHint.frame = NSRect(x: 150, y: excludedRowsHeight + 242, width: 534, height: 22)
        blackBody.setFrameSize(NSSize(width: 708, height: excludedRowsHeight + 272))
        if !blackBody.isHidden { blackBody.setFrameOrigin(NSPoint(x: 0, y: y)); y += blackBody.frame.height }
        // The contacts source belongs to the whitelist tab, but its existing
        // independent switch is not gated by the file-only whitelist toggle.
        contactsSection.isHidden = !white
        if white {
            contactsSection.setFrameOrigin(NSPoint(x: 0, y: y + 20))
            y = contactsSection.frame.maxY + 12
        }
        generalBody.setFrameOrigin(NSPoint(x: 0, y: y + 8))
        settingsDocument.setFrameSize(NSSize(width: 708, height: y + 8 + generalBody.frame.height))
    }
    @objc func changeScopeTab() {
        scopeOffsets[selectedScope] = scopePage.scroll.documentVisibleRect.minY
        selectedScope = scopePicker.selectedSegment
        layoutSettingsSections()
        let maxY = max(0, settingsDocument.bounds.height - scopePage.scroll.contentView.bounds.height)
        scopePage.scroll.contentView.scroll(to: NSPoint(x: 0, y: min(scopeOffsets[selectedScope], maxY)))
        scopePage.scroll.reflectScrolledClipView(scopePage.scroll.contentView)
        scopePage.updateHint()
    }
    @objc func addBlacklistScope() {
        let picker = NSOpenPanel(); picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.allowsMultipleSelection = true
        if picker.runModal() == .OK { excludedList.append(picker.urls.map { $0.path }) }
    }
    @objc func addScope() {
        let picker = NSOpenPanel(); picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.allowsMultipleSelection = true
        if picker.runModal() == .OK { scopeList.append(picker.urls.map { $0.path }) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender !== settingsWindow || !savingMode
    }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow {
            diagnosticGeneration += 1; lokiiRequestGeneration += 1; savingMode = false
            applyGlassTint(settings.effectiveGlassTintStrength); settingsWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }
    @objc func cancelSettings() {
        guard !savingMode else { return }
        lokiiRequestGeneration += 1; savingMode = false; applyGlassTint(settings.effectiveGlassTintStrength); settingsWindow?.close(); settingsWindow = nil }
    @objc func changeSearchMode() {
        modeHint.stringValue = modePicker.selectedSegment == 1
            ? "使用觅见内置 Lokii 引擎；原生扫描与监听暂停。保存后生效。"
            : "使用觅见原生名称索引；不运行 Lokii 引擎。保存后生效。"
        refreshButton.isEnabled = true
        lokiiDetails.stringValue = settings.effectiveSearchMode == .lokii ? lokiiNote : "引擎随觅见提供 · 无需安装 Lokii.app 或 CLI"
    }
    var lokiiCache: URL { storage.appendingPathComponent("LokiiEngine/v1") }
    func synchronizeLokiiAtLaunch() {
        lokiiScopeReady = false; lokiiNote = "正在启动内置引擎"; indexing = true
        updateStatus()
        let snapshot = settings, cache = lokiiCache
        connectionQueue.async { [weak self] in
            guard let self else { return }
            do { try self.lokiiProcess.start(settings: snapshot, cache: cache) }
            catch { DispatchQueue.main.async { [weak self] in
                guard let self, self.settings.effectiveSearchMode == .lokii else { return }
                self.lokiiScopeReady = false; self.indexing = false
                self.lokiiNote = "内置引擎启动失败：" + error.localizedDescription
                self.updateStatus(); self.lokiiDetails?.stringValue = self.lokiiNote
            } }
        }
    }
    func receiveLokiiStatus(_ value: [String: Any]) {
        guard settings.effectiveSearchMode == .lokii else { return }
        if let instance = value["instance"] as? Int, lokiiProcess.pid != Int32(instance) { return }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), data != lastLokiiStatusData {
            lastLokiiStatusData = data
            let file = lokiiCache.appendingPathComponent("runtime-state.json")
            connectionQueue.async { try? data.write(to: file, options: .atomic) }
        }
        let wasReady = lokiiScopeReady
        lokiiScopeReady = value["queryable"] as? Bool == true
        let phase = value["phase"] as? String ?? "unknown"
        indexing = ["initializing", "rebuilding", "calibrating", "replaying"].contains(phase)
        let title = ["awaitingConfiguration":"等待范围配置", "initializing":"正在建立索引", "rebuilding":"正在重建索引",
                     "calibrating":"正在校准范围", "replaying":"正在追赶文件变化", "incremental":"正在增量更新",
                     "ready":"索引就绪", "failed":"索引任务失败"][phase] ?? phase
        lokiiNote = title + " · \(value["count"] as? Int ?? 0) 项"
        if value["liveUpdates"] as? Bool == false && phase == "ready" { lokiiNote += " · 自动监听已关闭" }
        if value["networkScanning"] as? Bool == true { lokiiNote += " · 正在更新网络目录" }
        if let error = value["error"] as? String { lokiiNote += " · " + error }
        if let warnings = value["warnings"] as? [String], !warnings.isEmpty { lokiiNote += " · \(warnings.count) 处目录无法读取" }
        if lokiiScopeReady { lastScan = Date() }
        lokiiDetails?.stringValue = lokiiNote
        updateStatus()
        let generation = value["generation"] as? Int ?? 0
        let changed = generation != lokiiGeneration; lokiiGeneration = generation
        if panel.isVisible && !input.stringValue.isEmpty && (!wasReady && lokiiScopeReady || changed && !searching) { runSearch() }
    }
    func lokiiExited() {
        guard settings.effectiveSearchMode == .lokii else { return }
        let now = Date(); lokiiRestarts = lokiiRestarts.filter { now.timeIntervalSince($0) < 60 }
        guard lokiiRestarts.count < 2 else { lokiiNote += " · 已停止自动重试，请检查引擎"; updateStatus(); return }
        lokiiRestarts.append(now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.settings.effectiveSearchMode == .lokii else { return }
            self.synchronizeLokiiAtLaunch()
        }
    }
    @objc func openLokii() {
        let state = lokiiProcess.snapshot
        var detail = lokiiNote + "\n\n内置 lokii-core 0.1.9 · 独立辅助进程 \(lokiiProcess.pid.map(String.init) ?? "未运行")"
        detail += "\n缓存：" + lokiiCache.path
        detail += "\n范围已加载：\(state["loadedConfigRevision"] as? Int ?? 0) · 已校准：\(state["indexedConfigRevision"] as? Int ?? 0)"
        detail += "\n启动方式：\(state["startup"] as? String ?? "尚未启动")"
        if let warnings = state["warnings"] as? [String], !warnings.isEmpty { detail += "\n\n" + warnings.joined(separator: "\n") }
        detail += "\n\n不依赖官方 App、CLI 或全局配置。5000项为预取上限，不代表完整匹配总数。"
        alert("Lokii 引擎状态", detail)
    }
    @objc func checkLokiiConnection() {
        guard settings.effectiveSearchMode == .lokii else { lokiiDetails.stringValue = "保存为 Lokii 模式后，内置引擎会自动启动。"; return }
        if lokiiProcess.pid == nil { synchronizeLokiiAtLaunch(); return }
        connectionQueue.async { [weak self] in
            guard let self else { return }
            do { let state = try self.lokiiProcess.request("status")
                DispatchQueue.main.async { [weak self] in self?.receiveLokiiStatus(state) }
            } catch { DispatchQueue.main.async { [weak self] in self?.lokiiDetails?.stringValue = error.localizedDescription } }
        }
    }
    @objc func saveSettings() {
        guard !savingMode else { return }
        func lines(_ text: String) -> [String] { text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        var next = settings
        next.searchMode = modePicker.selectedSegment == 1 ? "lokii" : "native"
        next.pinnedItems = draftPins
        next.searchSystemSettings = systemSettingsButton.state == .on
        next.searchContacts = contactsButton.state == .on
        next.glassTintStrength = opacitySlider.doubleValue
        next.highlightStyle = draftStyle.rawValue
        next.whitelistEnabled = whiteToggle.state == .on; next.blacklistEnabled = blackToggle.state == .on
        next.blockedExtensions = blockedExtensionField.stringValue
        next.blockedKeywords = lines(blockedKeywordEditor.string)
        next.excludeFinderAliases = aliasExclusionButton.state == .on
        next.excludeSymbolicLinks = symlinkExclusionButton.state == .on
        next.roots = scopeList.paths.filter { !$0.isEmpty }; next.exclusions = excludedList.paths.filter { !$0.isEmpty }
        guard !next.usesWhitelist || !next.roots.isEmpty else { alert("请添加搜索目录", "至少保留一个目录。"); return }
        guard (next.roots + next.exclusions).allSatisfy({ $0.hasPrefix("/") || $0 == "~" || $0.hasPrefix("~/") }) else { alert("目录格式不正确", "请使用绝对路径或 ~/ 开头的路径。"); return }
        if typeSelectionChanged || legacyMigrationRequested {
            next.kinds = Set(categoryButtons.filter { $0.value.state == .on }.map { $0.key })
            next.legacyKinds = nil
        }
        next.allTypes = allButton.state == .on
        next.includeExtensionless = extensionlessButton.state == .on
        next.fontName = fontPopup.titleOfSelectedItem
        next.customExtensions = extensionField.stringValue; next.matchPath = matchPopup.selectedSegment == 1
        next.applicationsFirst = applicationsFirstButton.state == .on
        next.sortModified = sortPopup.selectedSegment == 1; next.limit = Settings.candidateLimits[limitPopup.selectedSegment]
        next.windowWidth = ["narrow", "medium", "wide"][widthPicker.selectedSegment]
        next.visibleRows = rowsPicker.selectedSegment + 3
        next.hotKey = hotPopup.indexOfSelectedItem; next.showHidden = hiddenButton.state == .on; next.autoRefresh = refreshButton.state == .on
        persistSettings(next)
    }
    func persistSettings(_ next: Settings) {
        do {
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(next).write(to: settingsURL, options: .atomic)
        } catch {
            alert("设置未保存", error.localizedDescription); return
        }
        let update = SettingsUpdate(from: settings, to: next)
        if update.modeChanged {
            diagnosticGeneration += 1
            _ = searchTicket.next(); pendingSearch?.cancel()
            stopNativeIndex(); results = []; displayedQuery = nil; table.reloadData()
            lokiiNote = "正在切换引擎"; lokiiQueryNote = ""; lokiiGeneration = -1
        }
        if update.scopeChanged {
            // Invalidate old asynchronous results before applying the new scope.
            _ = scanTicket.next(); _ = searchTicket.next()
            entries = []; results = []; lastScan = nil; indexing = false
        }
        let contactsJustEnabled = settings.searchContacts != true && next.searchContacts == true
        settings = next
        configureContacts(requestPermission: contactsJustEnabled)
        if settings.effectiveSearchMode == .native { lokiiScopeReady = false }
        if update.modeChanged || update.scopeChanged {
            searcher.async { [weak self] in self?.lokiiEngine.reset() }
        }
        if settings.effectiveSearchMode == .lokii {
            let desired = LokiiManagedConfig(settings: settings, cache: lokiiCache)
            if lokiiProcess.configuration != desired || lokiiProcess.pid == nil { synchronizeLokiiAtLaunch() }
        } else if update.modeChanged {
            connectionQueue.async { [weak self] in self?.lokiiProcess.stop() }
        }
        if !update.modeChanged && (update.scopeChanged || update.listenerChanged) {
            configureIndexWatcher(since: FSEventsGetCurrentEventId())
        }
        if update.modeChanged && settings.effectiveSearchMode == .native {
            // Load before capturing a query's source, then calibrate below.
            let cached = IndexSnapshot.load(from: indexURL, settings: settings)
            entries = cached?.entries ?? []; lastScan = cached?.updated; lastCalibration = cached?.calibrated
            configureIndexWatcher(since: FSEventsGetCurrentEventId())
        }
        applyGlassTint(settings.effectiveGlassTintStrength)
        input.font = searchFont(size: 32); centerInputField()
        if update.shortcutChanged { registerHotKey() }
        cancelSettings()
        if update.queryChanged { runSearch() }
        else { table.reloadData(); layoutResults(); syncScanMotion() }
        if update.needsScan { reindex() }

    }
}
LaunchEnvironment.sanitize()
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
