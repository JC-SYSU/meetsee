import Foundation

@main struct ApplicationPriorityTests {
    static func main() throws {
        let files = (0..<40).map { Entry(path: "/fixture/Test \($0).txt", directory: false, modified: Double($0)) }
        let apps = (0..<12).map { Entry(path: "/fixture/Z Test \($0).app", directory: true, modified: Double($0)) }
        let entries = files + apps
        var settings = Settings(); settings.roots = ["/fixture"]; settings.allTypes = true
        precondition(settings.applicationsFirst != true)
        let initial = settings
        settings.applicationsFirst = false
        precondition(!SettingsUpdate(from: initial, to: settings).queryChanged)
        for enabled in [false, true] {
            settings.applicationsFirst = enabled
            for modified in [false, true] {
                settings.sortModified = modified
                for limit in [1, 5, 10, 20, 50] {
                    settings.limit = limit
                    let result = search(entries, query: "Test", settings: settings)
                    let reference = referenceSearch(entries, query: "Test", settings: settings)
                    precondition(result.entries.map(\.path) == reference.entries.map(\.path))
                    precondition(result.total == 52)
                    if enabled { precondition(result.entries.prefix(min(limit, apps.count)).allSatisfy { $0.kind == .application }) }
                    else { precondition(result.entries.first?.kind != .application) }
                    let page = SettingsDestination(name: "Test", english: "Test", identifier: "test", parent: "")
                    let merged = mergeSettings(result, pages: [page], query: "Test", settings: settings)
                    precondition(merged.items.count <= settings.effectiveCandidateLimit)
                    if enabled { precondition(merged.items.first?.file?.kind == .application) }
                    else { precondition(merged.items.first?.file == nil) }
                }
            }
        }
        let change = SettingsUpdate(from: initial, to: settings)
        precondition(change.queryChanged && !change.needsScan)
        let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        precondition(restored.applicationsFirst == true)
        let legacy = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(initial))
        precondition(legacy.applicationsFirst == nil)
        settings.blacklistEnabled = true; settings.blockedKeywords = ["Z Test"]
        precondition(search(entries, query: "Test", settings: settings).entries.allSatisfy { $0.kind != .application })
        settings.blacklistEnabled = false
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("meetsee-priority-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("Test.txt"); try Data().write(to: file)
        let pin = try PinnedItem.make(term: "Test", target: file.path, name: "", others: [])
        settings.pinnedItems = [pin]; settings.limit = 5
        let found = search(entries, query: "Test", settings: settings)
        let base = mergeSettings(found, pages: [], query: "Test", settings: settings)
        let pinned = mergePinned(base, files: found, query: "Test", settings: settings)
        precondition(pinned.items.count == 5 && pinned.items[0].isPinned && pinned.items[0].file?.kind != .application)
        precondition(pinned.items.dropFirst().allSatisfy { $0.file?.kind == .application })
        let appPin = try PinnedItem.make(term: "Test", target: "https://example.com", name: "", others: [])
        settings.pinnedItems = [appPin]
        precondition(mergePinned(base, files: found, query: "Test", settings: settings).items.first?.webURL != nil)
        print("PASS: application priority before top-N and settings merge; pinned targets remain first; default/legacy, persistence, filtering, both sort modes, no rescan")
    }
}
