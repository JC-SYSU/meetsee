import Foundation
import CoreServices

/// FSEvents is a hint to reconcile directories, not a file-operation journal.
/// All callbacks and lifecycle calls run on the main queue.
final class IndexWatcher {
    private var stream: FSEventStreamRef?
    let receive: ([String], UInt64, Bool, Bool) -> Void
    init(receive: @escaping ([String], UInt64, Bool, Bool) -> Void) { self.receive = receive }
    func start(roots: [String], since: UInt64) -> Bool {
        stop()
        guard !roots.isEmpty else { return false }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, context, count, paths, flags, ids in
            guard let context else { return }
            let owner = Unmanaged<IndexWatcher>.fromOpaque(context).takeUnretainedValue()
            let names = unsafeBitCast(paths, to: NSArray.self) as! [String]
            var changed: [String] = []; var latest: UInt64 = 0; var fallback = false; var historyDone = false
            let unreliable = UInt32(kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)
            for i in 0..<count {
                latest = max(latest, ids[i])
                if flags[i] & unreliable != 0 { fallback = true }
                if flags[i] & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 { historyDone = true; continue }
                changed.append(names[i])
            }
            owner.receive(changed, latest, fallback, historyDone)
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        guard let created = FSEventStreamCreate(nil, callback, &context, roots as CFArray, since, 0.7, flags) else { return false }
        stream = created
        FSEventStreamSetDispatchQueue(created, .main)
        guard FSEventStreamStart(created) else { stop(); return false }
        return true
    }
    func stop() {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        stream = nil
    }
    deinit { stop() }
}

/// Ignore noise before it can schedule work. Only traversal exclusions belong
/// here: filtering by extension/keyword could hide a rename or type change.
func relevantIndexEventPaths(_ paths: [String], settings: Settings, ignored: String) -> [String] {
    let roots = IndexScope(settings).roots.sorted { $0.count < $1.count }
    let exclusions = BlacklistFilter(settings).directories
    return paths.filter { path in
        guard !within(path, ignored), !exclusions.contains(where: { within(path, $0) }),
              let root = roots.first(where: { within(path, $0) }) else { return false }
        guard !settings.showHidden, path != root else { return true }
        let components = path.dropFirst(root.count).split(separator: "/")
        var ancestor = root
        for (index, component) in components.enumerated() {
            if component.hasPrefix(".") { return false } // Also works for deleted paths.
            ancestor = (ancestor as NSString).appendingPathComponent(String(component))
            let url = URL(fileURLWithPath: ancestor)
            let values = try? url.resourceValues(forKeys: [.isHiddenKey, .isPackageKey, .isSymbolicLinkKey])
            // The leaf may have just become Finder-hidden: reconcile its parent
            // to remove a formerly visible entry. Hidden ancestors cannot be
            // traversed by the normal scanner, so their descendant noise is safe
            // to ignore. An explicitly configured hidden root is still allowed.
            if index < components.count - 1, values?.isHidden == true,
               !isSystemApplicationLink(url, symbolic: values?.isSymbolicLink == true) { return false }
            // App/package internals belong to the package entry, not separate
            // hidden-file candidates. Preserve package-name/metadata changes.
            if values?.isPackage == true { break }
        }
        return true
    }
}

/// Re-scan each changed item's parent so deletions, renames and package changes
/// remove old descendants as well. Never scan outside configured roots.
func affectedIndexDirectories(paths: [String], roots: [String], ignored: String) -> [String] {
    var candidates = Set<String>()
    for path in paths where !within(path, ignored) {
        guard let root = roots.filter({ within(path, $0) }).min(by: { $0.count < $1.count }) else { continue }
        var directory = path == root ? root : (path as NSString).deletingLastPathComponent
        // A directory inside a package is not independently indexed.
        var ancestor = directory
        while ancestor != root && within(ancestor, root) {
            if (try? URL(fileURLWithPath: ancestor).resourceValues(forKeys: [.isPackageKey]).isPackage) == true { directory = (ancestor as NSString).deletingLastPathComponent }
            let next = (ancestor as NSString).deletingLastPathComponent
            if next == ancestor { break }; ancestor = next
        }
        while directory != root && !FileManager.default.fileExists(atPath: directory) {
            directory = (directory as NSString).deletingLastPathComponent
        }
        candidates.insert(directory)
    }
    var result: [String] = []
    for path in candidates.sorted(by: { $0.count < $1.count }) where !result.contains(where: { within(path, $0) }) { result.append(path) }
    return result
}

func scanIndexChanges(_ directories: [String], settings: Settings, cancelled: () -> Bool) -> ScanResult {
    var local = settings
    // Directories have already been constrained to the original roots.
    local.whitelistEnabled = true; local.roots = directories
    return scan(local, cancelled: cancelled)
}

func mergingIndex(_ previous: [Entry], replacement: [Entry], directories: [String]) -> [Entry] {
    previous.filter { entry in !directories.contains(where: { within(entry.path, $0) }) } + replacement
}

/// Compare the replacement by identity rather than enumeration/Set order.
/// Modified time participates in ranking and icon cache invalidation, while
/// application aliases and pinyin also affect matches without changing counts.
func indexReplacementHasChanges(_ previous: [Entry], replacement: [Entry], directories: [String]) -> Bool {
    var remaining = Dictionary(replacement.map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
    for old in previous where directories.contains(where: { within(old.path, $0) }) {
        guard let new = remaining.removeValue(forKey: old.path),
              old.name == new.name, old.kind == new.kind, old.modified == new.modified,
              old.isFinderAlias == new.isFinderAlias, old.isSymbolicLink == new.isSymbolicLink,
              old.searchName == new.searchName, old.searchPath == new.searchPath,
              Set(old.searchAliases) == Set(new.searchAliases),
              Set(old.pinyin.full) == Set(new.pinyin.full),
              Set(old.pinyin.initials) == Set(new.pinyin.initials) else { return true }
    }
    return !remaining.isEmpty
}
