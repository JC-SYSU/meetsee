import Foundation
@main struct ManagedSearchTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("meetsee-managed-match-" + UUID().uuidString).resolvingSymlinksInPath()
        let scope = root.appendingPathComponent("scope")
        try fm.createDirectory(at: scope, withIntermediateDirectories: true)
        for name in ["旅行.txt", "README", ".hidden/旅行.txt", "父目录/笔记.txt", "Fake.app/Contents/旅行.txt", "Font Book.app/Contents/Info.plist"] {
            let file = scope.appendingPathComponent(name)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        let info: [String: Any] = ["CFBundleName": "Font Book", "CFBundleDisplayName": "字体册", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: scope.appendingPathComponent("Font Book.app/Contents/Info.plist"))
        var settings = Settings(); settings.searchMode = "lokii"; settings.roots = [scope.path]; settings.allTypes = true
        let process = LokiiProcess(); process.executable = URL(fileURLWithPath: CommandLine.arguments[1])
        defer { process.stop() }
        try process.start(settings: settings, cache: root.appendingPathComponent("cache"))
        let end = Date().addingTimeInterval(15)
        while process.snapshot["scopeSynchronized"] as? Bool != true && Date() < end { Thread.sleep(forTimeInterval: 0.03) }
        precondition(process.snapshot["scopeSynchronized"] as? Bool == true)
        let engine = LokiiEngine(process: process)
        for pathMode in [false, true] {
            settings.matchPath = pathMode
            for hidden in [false, true] {
                settings.showHidden = hidden
                if hidden { continue } // Changing traversal requires a new engine config, tested separately.
                let native = scan(settings)
                for query in ["旅行", "README", "父目录", "ztc", "字体册", "Font Book", "笔记", "旅行 txt"] {
                    let expected = search(native.entries, query: query, settings: settings)
                    let actual = try engine.searchFiles(query: query, settings: settings)
                    precondition(expected.entries.map(\.path) == actual.files.entries.map(\.path), "mode parity: " + query)
                }
            }
        }
        settings.matchPath = false; settings.showHidden = false; settings.blacklistEnabled = true; settings.blockedKeywords = ["字体册"]
        let blocked = try engine.searchFiles(query: "ztc", settings: settings)
        precondition(blocked.files.entries.isEmpty)
        settings.blockedKeywords = []; settings.applicationsFirst = true
        settings.pinnedItems = [try PinnedItem.make(term: "ztc", target: scope.appendingPathComponent("旅行.txt").path, name: "旅行", others: [])]
        let found = try engine.searchFiles(query: "ztc", settings: settings)
        let base = mergeSettings(found.files, pages: [], query: "ztc", settings: settings)
        precondition(mergePinned(base, files: found.files, query: "ztc", settings: settings, source: found.source).items.first?.isPinned == true)
        let oldPID = process.pid
        settings.fontName = "Menlo"
        try process.start(settings: settings, cache: root.appendingPathComponent("cache"))
        precondition(process.pid == oldPID, "presentation must not restart engine")
        print("PASS: real package-helper/native candidate identity+order parity, Chinese/mixed/path/extensionless/apps/pinyin; blacklist and pinned priority; presentation does not restart")
    }
}
