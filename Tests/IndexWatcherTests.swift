import Foundation
import CoreServices

@main struct IndexWatcherTests {
    static func wait(_ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(8)
        while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        precondition(predicate(), "Timed out waiting for real FSEvents")
    }
    static func main() throws {
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        let root = URL(fileURLWithPath: expandedPath(input.path))
        let folder = root.appendingPathComponent("子目录")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cache = root.appendingPathComponent("IndexCache").path
        var settings = Settings(); settings.roots = [root.path]; settings.allTypes = true
        let baseline = scan(settings).entries
        var observed: [String] = []; var history = false
        let checkpoint = FSEventsGetCurrentEventId()
        let watcher = IndexWatcher { paths, _, fallback, done in
            precondition(!fallback); observed += paths; history = history || done
        }
        precondition(watcher.start(roots: [root.path], since: checkpoint))
        let file = folder.appendingPathComponent("测试.txt")
        try Data("fixture".utf8).write(to: file)
        wait { observed.contains(file.path) }
        let dirs = affectedIndexDirectories(paths: observed, roots: [root.path], ignored: cache)
        precondition(dirs.contains(folder.path) || dirs.contains(root.path))
        var updated = mergingIndex(baseline, replacement: scanIndexChanges(dirs, settings: settings, cancelled: { false }).entries, directories: dirs)
        precondition(search(updated, query: "测试", settings: settings).total == 1)
        observed = []
        let renamed = folder.appendingPathComponent("改名.txt")
        try FileManager.default.moveItem(at: file, to: renamed)
        wait { observed.contains(renamed.path) }
        let renames = affectedIndexDirectories(paths: observed, roots: [root.path], ignored: cache)
        updated = mergingIndex(updated, replacement: scanIndexChanges(renames, settings: settings, cancelled: { false }).entries, directories: renames)
        precondition(search(updated, query: "测试", settings: settings).total == 0)
        precondition(search(updated, query: "改名", settings: settings).total == 1)
        observed = []
        try FileManager.default.removeItem(at: renamed) // Only this test's generated fixture.
        wait { observed.contains(renamed.path) }
        let deletes = affectedIndexDirectories(paths: observed, roots: [root.path], ignored: cache)
        updated = mergingIndex(updated, replacement: scanIndexChanges(deletes, settings: settings, cancelled: { false }).entries, directories: deletes)
        precondition(search(updated, query: "改名", settings: settings).total == 0)
        watcher.stop()
        observed = []; history = false
        precondition(watcher.start(roots: [root.path], since: checkpoint))
        wait { history }
        precondition(!observed.isEmpty, "Historical events should replay")
        watcher.stop()
        precondition(affectedIndexDirectories(paths: [cache + "/names.plist", "/elsewhere/file"], roots: [root.path], ignored: cache).isEmpty)
        precondition(affectedIndexDirectories(paths: [root.path, folder.path + "/x"], roots: [root.path], ignored: cache) == [root.path])
        let hiddenEvent = root.path + "/.SynologyWorkingDirectory/Temp/deleted-item"
        let ordinary = folder.path + "/file.txt"
        precondition(relevantIndexEventPaths([hiddenEvent, ordinary, cache + "/names.plist", "/elsewhere/file"], settings: settings, ignored: cache) == [ordinary])
        settings.showHidden = true
        precondition(relevantIndexEventPaths([hiddenEvent], settings: settings, ignored: cache) == [hiddenEvent])
        settings.showHidden = false
        settings.blacklistEnabled = true; settings.exclusions = [folder.path]
        precondition(relevantIndexEventPaths([ordinary], settings: settings, ignored: cache).isEmpty)
        settings.blacklistEnabled = false
        precondition(relevantIndexEventPaths([ordinary], settings: settings, ignored: cache) == [ordinary])
        var explicitHidden = settings
        explicitHidden.roots = [root.path + "/.explicit"]
        precondition(relevantIndexEventPaths([root.path + "/.explicit/file.txt"], settings: explicitHidden, ignored: cache).count == 1)
        let finderHidden = root.appendingPathComponent("FinderHidden")
        try FileManager.default.createDirectory(at: finderHidden, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isHidden = true
        var hiddenURL = finderHidden; try hiddenURL.setResourceValues(values)
        precondition(relevantIndexEventPaths([finderHidden.appendingPathComponent("file.txt").path], settings: settings, ignored: cache).isEmpty)
        precondition(relevantIndexEventPaths([finderHidden.path], settings: settings, ignored: cache) == [finderHidden.path],
            "Hidden-flag transitions on the event item must still reconcile its parent")
        let package = root.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let packageEvent = package.appendingPathComponent("Contents/.metadata").path
        precondition(relevantIndexEventPaths([packageEvent], settings: settings, ignored: cache) == [packageEvent])
        // Same-sized replacements can still change ranking, type, aliases or pinyin.
        let a = Entry(path: ordinary, directory: false, modified: 1)
        let b = Entry(path: folder.path + "/second.txt", directory: false, modified: 2)
        let outside = Entry(path: root.path + "/outside.txt", directory: false)
        precondition(!indexReplacementHasChanges([a,b,outside], replacement: [b,a], directories: [folder.path]))
        precondition(indexReplacementHasChanges([a,b], replacement: [b], directories: [folder.path]))
        precondition(indexReplacementHasChanges([a], replacement: [a,b], directories: [folder.path]))
        precondition(indexReplacementHasChanges([a], replacement: [Entry(path:ordinary,directory:false,modified:3)], directories:[folder.path]))
        precondition(indexReplacementHasChanges([a], replacement: [Entry(path:ordinary,directory:true,modified:1)], directories:[folder.path]))
        var changedPinyin = a; changedPinyin.pinyin.full = ["example"]
        precondition(indexReplacementHasChanges([a], replacement:[changedPinyin], directories:[folder.path]))
        var aliasObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as! [String:Any]
        aliasObject["searchAliases"] = ["alias-one", "alias-two"]
        let aliases = try JSONDecoder().decode(Entry.self, from: JSONSerialization.data(withJSONObject:aliasObject))
        precondition(indexReplacementHasChanges([a], replacement:[aliases], directories:[folder.path]))
        aliasObject["searchAliases"] = ["alias-two", "alias-one"]
        let reordered = try JSONDecoder().decode(Entry.self, from: JSONSerialization.data(withJSONObject:aliasObject))
        precondition(!indexReplacementHasChanges([aliases], replacement:[reordered], directories:[folder.path]))
        print("PASS: hidden/deleted/sync-noise event filtering, blacklist enablement, explicit hidden roots, Finder-hidden ancestors and package events")
        print("PASS: unchanged replacement skips requery; count/order-independent comparison detects metadata, aliases and pinyin changes")
        print("PASS: real FSEvents create/rename/delete, subtree merge, historical replay, root coalescing and cache exclusion")
    }
}
