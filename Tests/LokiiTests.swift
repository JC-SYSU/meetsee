import Foundation

@main struct LokiiTests {
    static func main() throws {
        let args = CommandLine.arguments
        let root = args[1], sockets = args[2]
        func client(_ suffix: String, timeout: Double = 0.8) -> LokiiClient {
            LokiiClient(path: sockets + "/" + suffix, timeout: timeout)
        }
        func fails(_ suffix: String, contains message: String, timeout: Double = 0.8) {
            do { _ = try client(suffix, timeout: timeout).query("test"); preconditionFailure("Expected failure: " + suffix) }
            catch { precondition(error.localizedDescription.contains(message), error.localizedDescription) }
        }
        let bulk = try client("bulk").query("item")
        precondition(bulk.results.count == 750, "must receive more than the old 500 cap")
        let response = try client("normal").query("中文 \" \\ \n type:app", limit: 17)
        precondition(response.results.count == 1 && response.results[0].isDir)
        fails("malformed", contains: "格式")
        fails("error", contains: "mock-error")
        fails("eof", contains: "完整响应")
        fails("oversize", contains: "过大")
        fails("absent", contains: "无法连接")
        let started = ProcessInfo.processInfo.systemUptime
        fails("stall", contains: "超时", timeout: 0.12)
        precondition(ProcessInfo.processInfo.systemUptime - started < 0.5)
        do { _ = try client("normal").query("test", cancelled: { true }); preconditionFailure("cancel") }
        catch { precondition(error.localizedDescription.contains("取消")) }
        print("PASS: JSON line transport, fragmented UTF-8, EOF, timeout, cancellation, malformed/error/oversized responses, missing service")

        var settings = Settings()
        precondition(settings.effectiveSearchMode == .native)
        settings.searchMode = "future-value"
        precondition(settings.effectiveSearchMode == .native)
        settings.searchMode = nil
        var lokii = settings; lokii.searchMode = "lokii"
        let update = SettingsUpdate(from: settings, to: lokii)
        precondition(update.modeChanged && update.queryChanged && !update.needsScan)
        precondition(SettingsUpdate(from: lokii, to: settings).needsScan)
        var changed = lokii; changed.roots = [root]; changed.showHidden = true
        precondition(!SettingsUpdate(from: lokii, to: changed).needsScan)
        let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(lokii))
        precondition(restored.effectiveSearchMode == .lokii)
        print("PASS: old/unknown settings default native; mode changes requery; only native re-entry/scope changes scan")

        settings.searchMode = "lokii"; settings.roots = [root]; settings.allTypes = true
        let engine = LokiiEngine(); engine.client = client("engine")
        let found = try engine.searchFiles(query: "旅行", settings: settings)
        precondition(found.files.entries.map(\.path).contains(root + "/旅行.txt"))
        precondition(!found.source.contains { $0.path.contains(".hidden") || $0.path.contains("Contents") || $0.path.contains("/outside/") })
        precondition(Set(found.source.map(\.path)).count == found.source.count)
        let hidden = Entry(path: root + "/.hidden/旅行.txt", directory: false)
        precondition(!found.source.contains { $0.path == hidden.path })
        let pinyin = try engine.searchFiles(query: "ztc", settings: settings)
        precondition(pinyin.files.entries.contains { $0.kind == .application && $0.name == "字体册" })
        precondition(!pinyin.files.entries.contains { $0.kind != .application })
        let english = try engine.searchFiles(query: "Font Book", settings: settings)
        precondition(english.files.entries.contains { $0.kind == .application })
        settings.blacklistEnabled = true; settings.blockedKeywords = ["字体册"]
        let blocked = try engine.searchFiles(query: "ztc", settings: settings)
        precondition(blocked.files.entries.isEmpty)
        settings.blockedKeywords = []; settings.allTypes = false; settings.kinds = [.image]
        let types = try engine.searchFiles(query: "旅行", settings: settings)
        precondition(types.files.entries.isEmpty)
        settings.allTypes = true; settings.matchPath = true
        let path = try engine.searchFiles(query: "父目录", settings: settings)
        precondition(path.files.entries.contains { $0.path == root + "/父目录/笔记.txt" })
        settings.applicationsFirst = true
        settings.pinnedItems = [try PinnedItem.make(term: "ztc", target: root + "/旅行.txt", name: "旅行", others: [])]
        let base = mergeSettings(pinyin.files, pages: [], query: "ztc", settings: settings)
        let pinned = mergePinned(base, files: pinyin.files, query: "ztc", settings: settings, source: pinyin.source)
        precondition(pinned.items.first?.isPinned == true)
        let report = diagnoseFile(path: root + "/旅行.txt", query: "旅行", settings: settings, entries: [], indexing: false, errors: [])
        precondition(report.contains("模式：Lokii") && !report.contains("暂不包含此对象"))
        settings.pinnedItems = []; settings.blacklistEnabled = false; settings.matchPath = false
        settings.applicationsFirst = false; settings.limit = 50
        let native = scan(settings)
        for term in ["旅行", "README", "父目录", "ztc", "Font Book"] {
            let local = search(native.entries, query: term, settings: settings)
            let remote = try engine.searchFiles(query: term, settings: settings)
            precondition(local.entries.map(\.path) == remote.files.entries.map(\.path), "mode parity: " + term)
        }
        engine.reset()
        print("PASS: matching/filter/sort parity against native fixture scan across Chinese, folders, extensionless files, application aliases and pinyin")
        print("PASS: Lokii-only adaptation, localized apps/English/pinyin, scope/hidden/packages/types/blacklist, deduplication, path query, pinned highest, mode-aware diagnostics")
    }
}
