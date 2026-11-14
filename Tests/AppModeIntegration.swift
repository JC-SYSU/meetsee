// Appended only to the test copy of main.swift. Uses an artificial scope.
let app = NSApplication.shared
let subject = AppDelegate()
let root = expandedPath(CommandLine.arguments[1])
subject.lokiiProcess.executable = URL(fileURLWithPath: CommandLine.arguments[2])
subject.lokiiProcess.onStatus = { value in DispatchQueue.main.async { subject.receiveLokiiStatus(value) } }
subject.settings.roots = [root]; subject.settings.allTypes = true; subject.settings.hotKey = 2
subject.buildPanel()
func awaitState(_ message: String, timeout: TimeInterval = 15, _ condition: () -> Bool) {
    let end = Date().addingTimeInterval(timeout)
    while !condition() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    if !condition() { FileHandle.standardError.write(Data(("FAILED: " + message + " | " + subject.lokiiNote + " | " + String(describing: subject.lokiiProcess.snapshot) + "\n").utf8)) }
    precondition(condition(), message)
}
subject.startNativeIndex()
awaitState("native scan") { !subject.indexing && !subject.entries.isEmpty }
subject.showSettings()
subject.modePicker.selectedSegment = 1; subject.changeSearchMode()
precondition(subject.settings.effectiveSearchMode == .native && subject.indexWatcher != nil)
subject.cancelSettings()
precondition(subject.settings.effectiveSearchMode == .native && !subject.entries.isEmpty)
print("PASS: mode draft/cancel leaves native engine intact")
subject.showSettings(); subject.modePicker.selectedSegment = 1; subject.changeSearchMode(); subject.saveSettings()
awaitState("managed core ready") { subject.settings.effectiveSearchMode == .lokii && subject.lokiiScopeReady && !subject.indexing }
precondition(subject.entries.isEmpty && subject.indexWatcher == nil && subject.lokiiProcess.pid != nil)
subject.input.stringValue = "ONLY_NATIVE"; subject.runSearch()
awaitState("managed query") { !subject.searching }
precondition(subject.results.contains { $0.file?.path == root + "/ONLY_NATIVE.txt" })
subject.entries = [Entry(path: root + "/INJECTED.txt", directory: false)]
subject.input.stringValue = "INJECTED"; subject.runSearch()
awaitState("no native fallback") { !subject.searching }
precondition(subject.results.isEmpty)
subject.settings.pinnedItems = [try PinnedItem.make(term: "INJECTED", target: root + "/ONLY_NATIVE.txt", name: "置顶目标", others: [])]
subject.runSearch(); awaitState("pinned") { !subject.searching }
precondition(subject.results.first?.isPinned == true)
subject.reindex()
awaitState("real rebuild accepted") { (subject.lokiiProcess.snapshot["job"] as? Int ?? 0) >= 2 }
awaitState("real rebuild completed") { subject.lokiiProcess.snapshot["scopeSynchronized"] as? Bool == true }
precondition(subject.indexWatcher == nil)
print("PASS: package-owned queries, no injected native fallback, highest-priority pins, real rebuild")
subject.showSettings(); subject.modePicker.selectedSegment = 0; subject.changeSearchMode(); subject.saveSettings()
awaitState("native resumes and child exits") { subject.settings.effectiveSearchMode == .native && !subject.indexing && subject.lokiiProcess.pid == nil }
precondition(subject.indexWatcher != nil && !subject.entries.isEmpty)
subject.stopNativeIndex(); subject.pendingSearch?.cancel(); _ = subject.searchTicket.next()
print("PASS: native re-entry restores watcher and stops owned helper")
var bootSettings = subject.settings; bootSettings.searchMode = "lokii"; bootSettings.pinnedItems = []
try JSONEncoder().encode(bootSettings).write(to: subject.settingsURL, options: .atomic)
let startup = AppDelegate()
startup.lokiiProcess.executable = URL(fileURLWithPath: CommandLine.arguments[2])
startup.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
awaitState("quiet persisted managed launch") { startup.lokiiScopeReady && !startup.indexing }
precondition(startup.entries.isEmpty && startup.indexWatcher == nil && !startup.panel.isVisible)
startup.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
precondition(startup.lokiiProcess.pid == nil)
print("PASS: saved Lokii mode starts quietly, restores private cache, exits with parent")
