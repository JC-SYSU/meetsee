// Appended to an isolated copy of AppDelegate; fake contacts, private pasteboard,
// no real Contacts access, no real file scan, no external application opening.
import Contacts
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let subject = AppDelegate()
subject.settings.roots = [expandedPath(CommandLine.arguments[1])]
subject.settings.searchSystemSettings = false
subject.settings.searchContacts = true
subject.settings.allTypes = true
subject.buildPanel()
var authorization = CNAuthorizationStatus.authorized
var requests = 0
let phone = ContactPhone(contactID: "fixture", numberID: "n1", name: "张三", label: "手机", rawNumber: "+86 138 0012 3456")
subject.contacts = ContactsSearch(authorization: { authorization }, request: { _ in requests += 1 }, load: { _ in ContactSearchIndex([phone]) }, notifications: NotificationCenter())
func wait(_ message: String, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    if !condition() { FileHandle.standardError.write(Data(String(describing: ("FAIL", message, "busy", subject.searching, "pending", subject.fileSearchPending, "items", subject.results.map { $0.name + ":" + ($0.contact == nil ? "file" : "contact") }, "state", subject.contacts.state, "indexHits", subject.contacts.index.search(subject.input.stringValue).count)).utf8)) }
    precondition(condition(), message)
}
subject.configureContacts()
wait("fake contacts ready") { subject.contacts.state == .ready }
precondition(requests == 0)
let root = expandedPath(CommandLine.arguments[1])
subject.entries = [Entry(path: root + "/张三.txt", directory: false)]
subject.input.stringValue = "张三"; subject.runSearch()
wait("mixed final native results") { !subject.searching && !subject.fileSearchPending && subject.results.count == 2 }
precondition(subject.results.filter { $0.contact != nil }.count == 1)
for query in ["张", "zhang", "zs", "13800123456"] {
    subject.input.stringValue = query; subject.runSearch()
    wait("nonexact completes") { !subject.searching && !subject.fileSearchPending }
    precondition(!subject.results.contains { $0.contact != nil }, query)
}
subject.settings.searchMode = "lokii" // intentionally unavailable: contacts remain usable
subject.lokiiScopeReady = false
subject.input.stringValue = "zhangsan"; subject.runSearch()
wait("contacts with unavailable Lokii") { !subject.searching && subject.results.first?.contact != nil }
precondition(subject.lokiiProcess.pid == nil)
// Deliberately block the file queue. Contact presentation must not wait behind it.
let unblock = DispatchSemaphore(value: 0), started = DispatchSemaphore(value: 0)
subject.searcher.async { started.signal(); _ = unblock.wait(timeout: .now() + 6) }
precondition(started.wait(timeout: .now() + 2) == .success)
subject.input.stringValue = "张三"; subject.runSearch()
wait("contact precedes blocked files") { !subject.searching && subject.fileSearchPending && subject.results.first?.contact != nil }
let cell = subject.tableView(subject.table, viewFor: subject.table.tableColumns.first, row: 0)!
let badge = cell.subviews.compactMap { $0 as? CandidateShortcutBadge }.first!
precondition(badge.restingLabel == "⌘C" && !badge.showNumber && !badge.isHidden)
precondition(cell.subviews.contains { ($0 as? NSImageView)?.image != nil })
let board = NSPasteboard(name: .init("meetsee-contacts-tests-" + UUID().uuidString))
defer { board.releaseGlobally(); unblock.signal() }
precondition(subject.copyContactNumber(to: board))
precondition(board.string(forType: .string) == "13800123456")
precondition(board.types?.contains(.string) == true && board.data(forType: .rtf) == nil && board.data(forType: .html) == nil && board.data(forType: .fileURL) == nil)
precondition(!subject.fileSearchPending)
unblock.signal()
// The copy invalidates the old query; changing to a non-contact never resurrects it.
subject.input.stringValue = "unrelated"; subject.runSearch()
wait("query invalidation") { !subject.searching }
precondition(subject.results.isEmpty)
subject.settings.searchMode = "native"
subject.input.stringValue = "张三"; subject.runSearch()
wait("contact again") { !subject.searching && !subject.fileSearchPending && subject.results.contains { $0.contact != nil } }
let row = subject.results.firstIndex { $0.contact != nil }!
subject.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
subject.panel.makeFirstResponder(subject.input)
subject.input.selectText(nil)
if let editor = subject.input.currentEditor() as? NSTextView {
    editor.setSelectedRange(NSRange(location: 0, length: 1))
    precondition(!subject.copyContactNumber(to: board), "selected text wins over contact copying")
    editor.setSelectedRange(NSRange(location: 1, length: 0))
} else { preconditionFailure("field editor unavailable") }
subject.searching = true
precondition(!subject.copyContactNumber(to: board))
subject.searching = false
// Runtime revoke must remove phones and must not overwrite the clipboard.
authorization = .denied; subject.contacts.refreshAuthorization()
precondition(!subject.results.contains { $0.contact != nil })
precondition(board.string(forType: .string) == "13800123456")
subject.settings.searchContacts = false; subject.configureContacts()
precondition(subject.contacts.state == .disabled)
subject.pendingSearch?.cancel(); _ = subject.searchTicket.next()
let scopeBefore = IndexScope(subject.settings)
subject.showSettings()
precondition(subject.contactsButton.state == .off)
precondition(subject.contactsButton.superview === subject.contactsSection)
precondition(subject.contactsStatus.superview === subject.contactsSection && subject.contactsPermissionButton.superview === subject.contactsSection)
precondition(subject.contactsSection.superview === subject.settingsDocument && !subject.contactsSection.isHidden)
precondition(subject.contactsSection.frame.minY > subject.whiteBody.frame.maxY)
let expandedY = subject.contactsSection.frame.minY
subject.allButton.state = .off; subject.layoutSettingsSections()
precondition(subject.contactsSection.frame.minY >= expandedY)
precondition(subject.contactsSection.frame.minY > subject.whiteBody.frame.maxY)
subject.allButton.state = .on
subject.whiteToggle.state = .off; subject.layoutSettingsSections()
precondition(subject.whiteBody.isHidden && !subject.contactsSection.isHidden)
precondition(subject.contactsButton.state == .off) // file switch doesn't rewrite source preference
subject.scopePicker.selectedSegment = 1; subject.changeScopeTab()
precondition(subject.contactsSection.isHidden)
subject.scopePicker.selectedSegment = 0; subject.changeScopeTab()
precondition(!subject.contactsSection.isHidden)
subject.whiteToggle.state = .on; subject.layoutSettingsSections()
precondition(subject.generalBody.frame.minY > subject.contactsSection.frame.maxY)
precondition(subject.settingsDocument.frame.maxY >= subject.generalBody.frame.maxY)
precondition(!subject.contactsStatus.stringValue.isEmpty && subject.contactsPermissionButton.isEnabled)
subject.contactsButton.state = .on
subject.saveSettings()
precondition(subject.settings.searchContacts == true && IndexScope(subject.settings) == scopeBefore && !subject.indexing)
let saved = try! JSONDecoder().decode(Settings.self, from: Data(contentsOf: subject.settingsURL))
precondition(saved.searchContacts == true)
subject.pendingSearch?.cancel(); _ = subject.searchTicket.next(); subject.contacts.onChange = nil; subject.contacts.setEnabled(false)
precondition(requests == 0)
print("PASS: real AppDelegate contact integration in both modes; blocked-file independence; copy badge; pure-text private clipboard; selected-text priority; stale query cancellation; revoke purges; no user data read")
