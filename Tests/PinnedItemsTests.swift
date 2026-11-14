import Foundation

@main struct PinnedItemsTests {
    static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("meetsee-pins-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("示例.txt")
        try Data("sample".utf8).write(to: file)
        let pin = try PinnedItem.make(term: " 项目 Project ", target: file.path, name: "常用文档", others: [])
        precondition(pin.term == "项目 Project" && pin.bookmark != nil)
        precondition(try! pin.resolve().name == "常用文档")
        func rejects(_ body: () throws -> Void) { do { try body(); preconditionFailure("Expected rejection") } catch {} }
        rejects { _ = try PinnedItem.make(term: "项目 PROJECT", target: file.path, name: "", others: [pin]) }
        for target in ["relative/file", "javascript:alert(1)", "ftp://example.com", "https://", "file://remote/tmp/a", "https://user:pass@example.com"] {
            rejects { _ = try PinnedItem.targetURL(target) }
        }
        let web = try PinnedItem.make(term: "文档docs", target: "https://example.com/docs", name: "", others: [pin])
        precondition(try! web.resolve().name == "example.com")
        let folder = try PinnedItem.make(term: "folder", target: root.absoluteString, name: "", others: [])
        precondition(try! folder.resolve().entry?.kind == .folder)
        var settings = Settings(); settings.roots = ["/no-such-scope"]; settings.pinnedItems = [pin, web]; settings.searchSystemSettings = false
        let empty = SearchResult(entries: [], total: 0)
        let merged = mergePinned(([], 0), files: empty, query: "项目 PROJECT", settings: settings)
        precondition(merged.items.count == 1 && merged.items[0].isPinned && merged.items[0].name == "常用文档")
        precondition(mergePinned(([], 0), files: empty, query: "项目", settings: settings).items.isEmpty)
        precondition(mergePinned(([], 0), files: empty, query: "文档docs", settings: settings).items.first?.webURL != nil)
        // Existing bindings gain phonetic aliases without adding saved fields.
        for query in ["xiangmuproject", " XMP "] {
            precondition(mergePinned(([], 0), files: empty, query: query, settings: settings).items.first?.name == "常用文档", query)
        }
        precondition(mergePinned(([], 0), files: empty, query: "xiangmu", settings: settings).items.isEmpty)
        precondition(mergePinned(([], 0), files: empty, query: "x", settings: settings).items.isEmpty)
        precondition(mergePinned(([], 0), files: empty, query: "changyongwendang", settings: settings).items.isEmpty)
        let chinese = try PinnedItem.make(term: "投稿", target: file.path, name: "投稿文档", others: [])
        let chineseFolder = try PinnedItem.make(term: "项目管理", target: root.path, name: "项目目录", others: [])
        let chineseWeb = try PinnedItem.make(term: "音乐", target: "https://example.com/music", name: "音乐网站", others: [])
        var phonetic = settings; phonetic.pinnedItems = [chinese, chineseFolder, chineseWeb]
        // Both engines share this merge; no scan or mode-specific aliases are needed.
        for mode in ["native", "lokii"] {
            phonetic.searchMode = mode
            for (query, name) in [("tougao", "投稿文档"), (" TG ", "投稿文档"),
                                  ("xiangmuguanli", "项目目录"), ("xmgl", "项目目录"),
                                  ("yinyue", "音乐网站"), ("yy", "音乐网站")] {
                let found = mergePinned(([], 0), files: empty, query: query, settings: phonetic)
                precondition(found.items.first?.isPinned == true && found.items.first?.name == name, mode + ":" + query)
            }
        }
        let collision = try PinnedItem.make(term: "推广", target: "https://example.com/promote", name: "推广网站", others: [])
        let explicit = try PinnedItem.make(term: "tg", target: "https://example.com/explicit", name: "手动检索词", others: [])
        phonetic.pinnedItems = [chinese, collision]
        precondition(mergePinned(([], 0), files: empty, query: "tg", settings: phonetic).items.first?.name == "投稿文档")
        phonetic.pinnedItems = [collision, chinese]
        precondition(mergePinned(([], 0), files: empty, query: "tg", settings: phonetic).items.first?.name == "推广网站")
        phonetic.pinnedItems = [chinese, collision, explicit]
        precondition(mergePinned(([], 0), files: empty, query: "tg", settings: phonetic).items.first?.name == "手动检索词")
        phonetic.pinnedItems = [chinese]; phonetic.applicationsFirst = true
        let app = Entry(path: root.appendingPathComponent("tg.app").path, directory: true)
        let appResult = SearchResult(entries: [app], total: 1)
        precondition(mergePinned(([.file(app)], 1), files: appResult, query: "tg", settings: phonetic).items.first?.isPinned == true)
        let restoredPhonetic = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(phonetic))
        precondition(restoredPhonetic.pinnedItems == phonetic.pinnedItems)
        precondition(mergePinned(([], 0), files: empty, query: "tg", settings: restoredPhonetic).items.first?.isPinned == true)
        phonetic.blacklistEnabled = true; phonetic.exclusions = [root.path]
        precondition(mergePinned(([], 0), files: empty, query: "tg", settings: phonetic).warning != nil)
        let entry = try pin.resolve().entry!
        let files = SearchResult(entries: [entry], total: 1)
        let deduped = mergePinned(([.file(entry)], 1), files: files, query: pin.term, settings: settings)
        precondition(deduped.items.count == 1 && deduped.total == 1)
        settings.blacklistEnabled = true; settings.exclusions = [root.path]
        precondition(mergePinned(([], 0), files: empty, query: pin.term, settings: settings).warning != nil)
        precondition(mergePinned(([], 0), files: empty, query: web.term, settings: settings).items.count == 1)
        settings.exclusions = []; settings.blockedExtensions = "txt"
        precondition(mergePinned(([], 0), files: empty, query: pin.term, settings: settings).items.isEmpty)
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        precondition(decoded.pinnedItems == settings.pinnedItems)
        var old = Settings(); let new = settings
        old.pinnedItems = nil
        var pinOnly = old; pinOnly.pinnedItems = [pin]
        precondition(SettingsUpdate(from: old, to: pinOnly).queryChanged && !SettingsUpdate(from: old, to: pinOnly).needsScan)
        _ = new
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        object.removeValue(forKey: "pinnedItems")
        let legacy = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: object))
        precondition(legacy.pinnedItems == nil)
        var capped = Settings(); capped.roots = [root.path]; capped.allTypes = true; capped.limit = 5
        capped.pinnedItems = [try PinnedItem.make(term: "示例", target: file.path, name: "", others: [])]
        let belowCap = mergePinned(([], 6), files: SearchResult(entries: [], total: 6), query: "示例", settings: capped, source: [entry])
        precondition(belowCap.total == 6 && belowCap.items.first?.isPinned == true)
        let link = root.appendingPathComponent("链接.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let linkPin = try PinnedItem.make(term: "link", target: link.path, name: "", others: [])
        precondition(try! linkPin.resolve().entry?.isSymbolicLink == true)
        var linkSettings = Settings(); linkSettings.pinnedItems = [linkPin]
        linkSettings.blacklistEnabled = true; linkSettings.excludeSymbolicLinks = true
        precondition(mergePinned(([], 0), files: empty, query: "link", settings: linkSettings).warning != nil)
        let moved = root.appendingPathComponent("已移动.txt")
        try FileManager.default.moveItem(at: file, to: moved)
        precondition(try! pin.resolve().url.resolvingSymlinksInPath().path == moved.resolvingSymlinksInPath().path)
        try FileManager.default.removeItem(at: moved)
        precondition(mergePinned(([], 0), files: empty, query: pin.term, settings: pinOnly).warning != nil)
        print("PASS: 常用置顶：完整混输、自动全拼/首字母、两引擎、手动词优先/冲突顺序、过滤与最高置顶、持久化、移动和失效")
    }
}
