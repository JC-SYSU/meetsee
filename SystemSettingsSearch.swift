import Foundation

struct SettingsDestination {
    let name: String
    let english: String
    let identifier: String
    let parent: String
    var url: URL { URL(string: "x-apple.systempreferences:" + identifier)! }
    var aliases: [String] { [name, english].map(normalized) }
    static let catalog: [SettingsDestination] = [
        .init(name: "网络", english: "Network", identifier: "com.apple.Network-Settings.extension", parent: ""),
        .init(name: "通知", english: "Notifications", identifier: "com.apple.Notifications-Settings.extension", parent: ""),
        .init(name: "专注模式", english: "Focus", identifier: "com.apple.Focus-Settings.extension", parent: ""),
        .init(name: "桌面与程序坞", english: "Desktop Dock", identifier: "com.apple.Desktop-Settings.extension", parent: ""),
        .init(name: "墙纸", english: "Wallpaper 壁纸", identifier: "com.apple.Wallpaper-Settings.extension", parent: ""),
        .init(name: "用户与群组", english: "Users Groups", identifier: "com.apple.Users-Groups-Settings.extension", parent: ""),
        .init(name: "互联网账户", english: "Internet Accounts", identifier: "com.apple.Internet-Accounts-Settings.extension", parent: ""),
        .init(name: "打印机与扫描仪", english: "Printers Scanners", identifier: "com.apple.Print-Scan-Settings.extension", parent: ""),
        .init(name: "触控 ID 与密码", english: "Touch ID Password", identifier: "com.apple.Touch-ID-Settings.extension", parent: ""),
        .init(name: "聚焦", english: "Spotlight", identifier: "com.apple.Spotlight-Settings.extension", parent: ""),
        .init(name: "关于本机", english: "About", identifier: "com.apple.SystemProfiler.AboutExtension", parent: "通用"),
        .init(name: "储存空间", english: "Storage 存储", identifier: "com.apple.settings.Storage", parent: "通用"),
        .init(name: "登录项与扩展", english: "Login Items Extensions 自启", identifier: "com.apple.LoginItems-Settings.extension", parent: "通用"),
        .init(name: "共享", english: "Sharing", identifier: "com.apple.Sharing-Settings.extension", parent: "通用"),
        .init(name: "语言与地区", english: "Language Region", identifier: "com.apple.Localization-Settings.extension", parent: "通用"),
        .init(name: "启动磁盘", english: "Startup Disk", identifier: "com.apple.Startup-Disk-Settings.extension", parent: "通用"),
        .init(name: "Wi-Fi", english: "wifi 无线网络", identifier: "com.apple.wifi-settings-extension", parent: ""),
        .init(name: "蓝牙", english: "Bluetooth", identifier: "com.apple.BluetoothSettings", parent: ""),
        .init(name: "声音", english: "Sound 音量", identifier: "com.apple.Sound-Settings.extension", parent: ""),
        .init(name: "键盘", english: "Keyboard", identifier: "com.apple.Keyboard-Settings.extension", parent: ""),
        .init(name: "显示器", english: "Displays 屏幕", identifier: "com.apple.Displays-Settings.extension", parent: ""),
        .init(name: "鼠标", english: "Mouse", identifier: "com.apple.Mouse-Settings.extension", parent: ""),
        .init(name: "触控板", english: "Trackpad", identifier: "com.apple.Trackpad-Settings.extension", parent: ""),
        .init(name: "外观", english: "Appearance 深色模式", identifier: "com.apple.Appearance-Settings.extension", parent: ""),
        .init(name: "辅助功能", english: "Accessibility", identifier: "com.apple.Accessibility-Settings.extension", parent: ""),
        .init(name: "隐私与安全性", english: "Privacy Security 权限", identifier: "com.apple.settings.PrivacySecurity.extension", parent: ""),
        .init(name: "锁定屏幕", english: "Lock Screen 锁屏", identifier: "com.apple.Lock-Screen-Settings.extension", parent: ""),
        .init(name: "电池", english: "Battery 电源", identifier: "com.apple.Battery-Settings.extension", parent: ""),
        .init(name: "屏幕使用时间", english: "Screen Time", identifier: "com.apple.Screen-Time-Settings.extension", parent: ""),
        .init(name: "软件更新", english: "Software Update", identifier: "com.apple.Software-Update-Settings.extension", parent: "通用"),
        .init(name: "日期与时间", english: "Date Time", identifier: "com.apple.Date-Time-Settings.extension", parent: "通用"),
        .init(name: "时间机器", english: "Time Machine 备份", identifier: "com.apple.Time-Machine-Settings.extension", parent: "通用"),
        .init(name: "隔空投送与接力", english: "AirDrop Handoff", identifier: "com.apple.AirDrop-Handoff-Settings.extension", parent: "通用"),
        .init(name: "传输或还原", english: "Transfer Reset", identifier: "com.apple.Transfer-Reset-Settings.extension", parent: "通用")
    ]
    // Only expose catalog pages explicitly supported by the installed OS.
    static func available() -> [SettingsDestination] {
        let root = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions")
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let ids = Set(urls.compactMap { url -> String? in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let attrs = plist["EXAppExtensionAttributes"] as? [String: Any],
                  let settings = attrs["SettingsExtensionAttributes"] as? [String: Any],
                  settings["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true else { return nil }
            return plist["CFBundleIdentifier"] as? String
        })
        return catalog.filter { ids.contains($0.identifier) }
    }
}

enum SearchCandidate {
    case file(Entry)
    case setting(SettingsDestination)
    case contact(ContactPhone)
    case pinned(ResolvedPin)
    var selectionIdentity: String {
        switch self {
        case .contact(let phone): return "contact:" + phone.identity
        case .file(let entry): return "file:" + entry.path
        case .setting(let page): return "setting:" + page.identifier
        case .pinned(let pin): return "pinned:" + pin.url.absoluteString
        }
    }
    var file: Entry? { switch self { case .file(let e): return e; case .pinned(let p): return p.entry; default: return nil } }
    var contact: ContactPhone? { if case .contact(let phone) = self { return phone }; return nil }
    var isPinned: Bool { if case .pinned = self { return true }; return false }
    var webURL: URL? { if case .pinned(let p) = self, !p.url.isFileURL { return p.url }; return nil }
    var name: String { switch self { case .contact(let phone): return phone.name; case .file(let e): return e.name; case .setting(let s): return s.name; case .pinned(let p): return p.name } }
    var subtitle: String { switch self {
    case .contact(let phone): return phone.subtitle
    case .file(let e): return (e.path as NSString).abbreviatingWithTildeInPath
    case .setting(let s): return "系统设置 · " + (s.parent.isEmpty ? s.name : s.parent + " › " + s.name)
    case .pinned(let p): return p.url.isFileURL ? (p.url.path as NSString).abbreviatingWithTildeInPath : p.url.absoluteString
    } }
}

func mergePinned(_ base: (items: [SearchCandidate], total: Int), files: SearchResult, query: String, settings: Settings, source: [Entry] = []) -> (items: [SearchCandidate], total: Int, warning: String?) {
    let pins = settings.pinnedItems ?? []
    // Explicit terms always win over generated aliases; alias collisions follow list order.
    guard let item = pins.first(where: { PinnedItem.key($0.term) == PinnedItem.key(query) })
        ?? pins.first(where: { $0.matchesPinyin(query) }) else { return (base.items, base.total, nil) }
    do {
        let pin = try item.resolve()
        if let entry = pin.entry, BlacklistFilter(settings).rejects(entry) {
            return (base.items, base.total, "置顶目标被黑名单排除")
        }
        let remaining = base.items.filter { $0.file?.path != pin.entry?.path || $0.file == nil }
        let duplicate = pin.entry.map { e in
            if files.entries.contains(where: { $0.path == e.path }) { return true }
            // A matching target may be below the normal result cap.
            guard let indexed = source.first(where: { $0.path == e.path }) else { return false }
            return search([indexed], query: query, settings: settings).total > 0
        } ?? false
        return (Array(([.pinned(pin)] + remaining).prefix(settings.effectiveCandidateLimit)), base.total + (duplicate ? 0 : 1), nil)
    } catch { return (base.items, base.total, "置顶目标不可用：" + error.localizedDescription) }
}

func mergeSettings(_ files: SearchResult, pages: [SettingsDestination], query: String, settings: Settings, contacts: [ContactPhone] = []) -> (items: [SearchCandidate], total: Int) {
    if settings.searchSystemSettings == false && (settings.searchContacts != true || contacts.isEmpty) { return (files.entries.map(SearchCandidate.file), files.total) }
    let q = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !q.isEmpty else { return ([], 0) }
    let terms = q.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    func score(_ aliases: [String]) -> Int { aliases.contains(q) ? 0 : (aliases.contains { $0.hasPrefix(q) } ? 1 : 2) }
    let matches = settings.searchSystemSettings == false ? [] : pages.filter { s in terms.allSatisfy { term in s.aliases.contains { $0.contains(term) } } }
    let people = settings.searchContacts == true ? contacts : []
    var hits = files.entries.enumerated().map { index, entry in
        let byName = terms.allSatisfy { term in entry.searchAliases.contains { $0.contains(term) } }
        let byPath = settings.matchPath && terms.allSatisfy { term in entry.searchPath.contains(term) || entry.searchAliases.contains { $0.contains(term) } }
        return (SearchCandidate.file(entry), byName ? score(entry.searchAliases) : (byPath ? 3 : 4), index)
    }
    hits += matches.enumerated().map { (SearchCandidate.setting($0.element), score($0.element.aliases), files.entries.count + $0.offset) }
    hits += people.enumerated().map { (SearchCandidate.contact($0.element), 0, files.entries.count + matches.count + $0.offset) }
    hits.sort {
        if settings.applicationsFirst == true, ($0.0.file?.kind == .application) != ($1.0.file?.kind == .application) {
            return $0.0.file?.kind == .application
        }
        return $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 < $1.1
    }
    return (Array(hits.prefix(settings.effectiveCandidateLimit).map { $0.0 }), files.total + matches.count + people.count)
}

// nil means the row count changed. Otherwise update only changed cells, keeping
// NSTableRowView and its already-presented HDR surface alive during index refresh.
func candidateRowsNeedingReload(_ old: [SearchCandidate], _ new: [SearchCandidate]) -> IndexSet? {
    guard old.count == new.count else { return nil }
    return IndexSet(old.indices.filter { index in
        let a = old[index], b = new[index]
        return a.selectionIdentity != b.selectionIdentity || a.name != b.name || a.subtitle != b.subtitle
            || a.file?.kind != b.file?.kind || a.file?.modified != b.file?.modified
            || a.file?.isFinderAlias != b.file?.isFinderAlias || a.file?.isSymbolicLink != b.file?.isSymbolicLink
    })
}
