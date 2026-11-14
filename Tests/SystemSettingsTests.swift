import Foundation
@main struct SystemSettingsTests {
    static func main() throws {
        let empty = SearchResult(entries: [], total: 0)
        var settings = Settings()
        precondition(settings.searchSystemSettings == nil)
        for query in ["蓝牙", "Bluetooth", "键盘", "Keyboard", "软件更新", "登录项"] {
            let result = mergeSettings(empty, pages: SettingsDestination.catalog, query: query, settings: settings)
            precondition(result.total > 0 && result.items.first!.file == nil)
        }
        precondition(mergeSettings(empty, pages: SettingsDestination.catalog, query: "", settings: settings).total == 0)
        precondition(!SettingsDestination.catalog.contains { $0.url.absoluteString.contains("?") })
        settings.searchSystemSettings = false
        precondition(mergeSettings(empty, pages: SettingsDestination.catalog, query: "键盘", settings: settings).total == 0)
        let update = SettingsUpdate(from: Settings(), to: settings)
        precondition(update.queryChanged && !update.needsScan)
        let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        precondition(restored.searchSystemSettings == false)
        settings.searchSystemSettings = true; settings.limit = 5
        let many = Array(repeating: SettingsDestination.catalog.first!, count: 10)
        let result = mergeSettings(empty, pages: many, query: "网络", settings: settings)
        precondition(result.total == 10 && result.items.count == 5)
        let live = SettingsDestination.available()
        precondition(!live.isEmpty)
        print("PASS: settings bilingual matching, file isolation, no deep links, toggle persistence, no rescan, count limit; available pages:", live.count)
    }
}
