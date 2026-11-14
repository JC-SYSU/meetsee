import Foundation
@main struct IndexCacheTests {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let url = root.appendingPathComponent("cache/names.plist")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var settings = Settings(); settings.roots = [expandedPath(root.path)]
        let entry = Entry(path: URL(fileURLWithPath: expandedPath(root.path)).appendingPathComponent("示例.txt").path, directory: false)
        precondition(IndexSnapshot.load(from: url, settings: settings) == nil)
        try IndexSnapshot.save([entry], settings: settings, updated: Date(timeIntervalSince1970: 123), to: url)
        let restored = IndexSnapshot.load(from: url, settings: settings)!
        precondition(restored.entries.first?.path == entry.path && restored.updated.timeIntervalSince1970 == 123)
        var changed = settings; changed.fontName = "MiSans"
        precondition(IndexSnapshot.load(from: url, settings: changed) != nil)
        changed.roots = ["/Applications"]
        precondition(IndexSnapshot.load(from: url, settings: changed) == nil)
        changed = settings; changed.showHidden = true
        precondition(IndexSnapshot.load(from: url, settings: changed) == nil)
        changed = settings; changed.blacklistEnabled = true; changed.blockedKeywords = ["示例"]
        precondition(IndexSnapshot.load(from: url, settings: changed) == nil)
        changed = settings; changed.kinds = [.application]
        precondition(search(restored.entries, query: "示例", settings: changed).entries.isEmpty)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        precondition((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try Data("invalid".utf8).write(to: url)
        precondition(IndexSnapshot.load(from: url, settings: settings) == nil)
        let old = IndexSnapshot(version: 1, eventID: nil, calibrated: nil, scope: IndexScope(settings), updated: Date(), entries: [entry])
        try PropertyListEncoder().encode(old).write(to: url)
        precondition(IndexSnapshot.load(from: url, settings: settings) == nil, "Old application classification requires a fresh index")
        let future = IndexSnapshot(version: 99, eventID: nil, calibrated: nil, scope: IndexScope(settings), updated: Date(), entries: [entry])
        try PropertyListEncoder().encode(future).write(to: url)
        precondition(IndexSnapshot.load(from: url, settings: settings) == nil)
        print("PASS: index persistence, scope invalidation, query filtering, corruption/version fallback and private permissions")
    }
}
