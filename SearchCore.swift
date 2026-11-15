import Foundation
import Darwin
import UniformTypeIdentifiers

enum FileKind: String, Codable, CaseIterable {
    case application, folder, document, text, image, audio, video, archive, script, other
    var label: String {
        switch self {
        case .application: return "应用"; case .folder: return "文件夹"
        case .document: return "文档"; case .text: return "文本"
        case .image: return "图片"; case .audio: return "音频"; case .video: return "视频"; case .archive: return "压缩与映像"
        case .script: return "代码与配置"; case .other: return "其他"
        }
    }
    static var displayed: [FileKind] { [.application, .folder, .document, .image, .audio, .video, .script, .archive, .other] }
    var examples: String {
        switch self {
        case .application: return "应用程序：.app 等"
        case .folder: return "普通文件夹；不按扩展名识别"
        case .document, .text: return "办公与阅读：.pdf .docx .xlsx .pptx\n.txt .md .rtf .epub 等"
        case .image: return "图片：.jpg .png .heic .gif .svg .tiff 等"
        case .audio: return "音频：.mp3 .m4a .wav .flac .aiff 等"
        case .video: return "视频：.mp4 .mov .mkv .avi .webm 等"
        case .script: return "代码与配置：.py .js .swift .sh\n.json .yaml .toml 等"
        case .archive: return "压缩包与磁盘映像：.zip .7z .rar\n.tar .gz .dmg .iso 等"
        case .other: return "未归入以上类别的文件"
        }
    }
    static func classify(_ url: URL, directory: Bool, legacy: Bool = false) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if directory { return ext == "app" ? .application : .folder }
        if !legacy {
            if ["mp3", "m4a", "wav", "flac", "aiff", "aac", "ogg", "opus"].contains(ext) { return .audio }
            if ["mp4", "mov", "mkv", "avi", "webm", "m4v", "mpeg"].contains(ext) { return .video }
            if ["json", "yaml", "yml", "toml", "xml", "ini", "conf", "ts", "tsx", "jsx", "css", "html", "c", "h", "cpp", "go", "rs", "java", "rb"].contains(ext) { return .script }
            if ext == "iso" { return .archive }
        }
        if ["applescript", "scpt", "sh", "py", "js", "swift"].contains(ext) { return .script }
        if ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg"].contains(ext) { return .archive }
        if ["pdf", "doc", "docx", "xls", "xlsx", "xlsm", "xlsb", "ppt", "pptx", "pages", "numbers", "key", "epub"].contains(ext) { return .document }
        if let t = UTType(filenameExtension: ext) {
            if !legacy && t.conforms(to: .audio) { return .audio }
            if !legacy && t.conforms(to: .movie) { return .video }
            if t.conforms(to: .image) { return .image }
            if t.conforms(to: .text) { return .text }
            if t.conforms(to: .archive) { return .archive }
        }
        return .other
    }
}

func normalized(_ s: String) -> String {
    s.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
}
func expandedPath(_ path: String) -> String {
    let expanded = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    guard let resolved = realpath(expanded, nil) else { return expanded }
    defer { free(resolved) }
    return String(cString: resolved)
}
func within(_ path: String, _ root: String) -> Bool {
    path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
}

enum HighlightStyle: String, CaseIterable {
    case mist, pearl, marker, graphite, porcelain
    /// Graphite remains decodable for existing preferences but is no longer offered.
    static var selectable: [HighlightStyle] { [.mist, .pearl, .marker, .porcelain] }
    var title: String {
        switch self {
        case .mist: return "01  天青 · 柔光釉色"
        case .pearl: return "02  柔白 · 轻浮层"
        case .marker: return "03  蓝标 · 浓蓝底"
        case .graphite: return "04  石墨 · 深色底（旧版）"
        case .porcelain: return "04  釉绿 · 蓝标形态"
        }
    }
    var detail: String {
        switch self {
        case .mist: return "蓝中含青的温润釉色，保留 HDR 柔光；无描边。"
        case .pearl: return "乳白渐变，上暗下亮，变化克制。"
        case .marker: return "克莱因蓝意向的实心底，白字与饱和蓝形成鲜明对比。"
        case .graphite: return "旧版实心石墨黑底；已隐藏，选择会回退到天青。"
        case .porcelain: return "实心釉绿高亮与瓷白色半透明面板；内凹釉面渲染仍在打磨中。"
        }
    }
}

/// Temporary hidden switch. While the recessed glaze renderer is still being
/// polished, the porcelain entry routes to a Marker-based lite treatment:
/// solid glaze-green selection plus a translucent porcelain veil over the HUD.
/// Flip `lite` to false to return to the full ceramic renderer.
enum PorcelainTheme {
    static let lite = true
}

extension HighlightStyle {
    var usesPorcelainLite: Bool { self == .porcelain && PorcelainTheme.lite }
}

enum SearchMode: String { case native, lokii }

struct Settings: Codable {
    var searchMode: String? = nil
    var effectiveSearchMode: SearchMode { SearchMode(rawValue: searchMode ?? "") ?? .native }
    var pinnedItems: [PinnedItem]? = nil
    var searchSystemSettings: Bool? = nil
    var searchContacts: Bool? = nil
    var applicationsFirst: Bool? = nil
    var scanMotion: String? = nil
    var categoryVersion: Int? = 2
    var legacyKinds: Set<FileKind>? = nil
    mutating func migrateCategories() {
        guard categoryVersion == nil else { return }
        legacyKinds = kinds
        if kinds.contains(.text) { kinds.insert(.document) }
        if kinds.contains(.other) { kinds.formUnion([.audio, .video]) }
        categoryVersion = 2
    }
    func includesKind(_ entry: Entry) -> Bool {
        if let legacyKinds {
            return legacyKinds.contains(FileKind.classify(URL(fileURLWithPath: entry.path), directory: entry.kind == .folder || entry.kind == .application, legacy: true))
        }
        return kinds.contains(entry.kind) || (entry.kind == .text && kinds.contains(.document))
    }
    var glassTintStrength: Double? = nil
    var effectiveGlassTintStrength: Double {
        let value = glassTintStrength ?? 0.3
        return value.isFinite ? (min(1, max(0, value)) * 10).rounded() / 10 : 0.3
    }
    var highlightStyle: String? = nil
    var effectiveHighlightStyle: HighlightStyle {
        let style = HighlightStyle(rawValue: highlightStyle ?? "") ?? .mist
        return style == .graphite ? .mist : style
    }
    var whitelistEnabled: Bool? = nil
    var blacklistEnabled: Bool? = nil
    var excludeFinderAliases: Bool? = nil
    var excludeSymbolicLinks: Bool? = nil
    var blockedExtensions: String? = nil
    var blockedKeywords: [String]? = nil
    var usesWhitelist: Bool { whitelistEnabled ?? true }
    var searchRoots: [String] { usesWhitelist ? roots : ["~"] }
    // Preserve existing exclusions on migration; new installations default to off.
    var usesBlacklist: Bool { blacklistEnabled ?? !exclusions.isEmpty }
    var roots: [String] = ["/Applications", "/System/Applications", "~/Applications"]
    var exclusions: [String] = []
    var kinds: Set<FileKind> = [.application, .folder, .document, .text, .image]
    var allTypes = false
    var customExtensions = ""
    var matchPath = false
    var showHidden = false
    var sortModified = false
    var whiteOverlayOpacity: Double? = nil
    var effectiveWhiteOverlayOpacity: Double {
        let value = whiteOverlayOpacity ?? 0
        return value.isFinite ? (min(1, max(0, value)) * 10).rounded() / 10 : 0
    }
    var windowWidth: String? = nil
    var visibleRows: Int? = nil
    var effectiveWindowWidth: Double {
        switch windowWidth { case "narrow": return 600; case "wide": return 840; default: return 720 }
    }
    var effectiveVisibleRows: Int { min(8, max(3, visibleRows ?? 5)) }
    static let candidateLimits = [5, 10, 20, 30, 50]
    var effectiveCandidateLimit: Int {
        Self.candidateLimits.first(where: { $0 >= limit }) ?? 50
    }
    var limit = 20
    var hotKey = 3
    var autoRefresh = true
    var includeExtensionless: Bool? = nil
    var fontName: String? = nil
    var effectiveFontName: String { fontName ?? "Maple Mono NF CN" }
}

struct ApplicationPinyin {
    var full: [String] = []
    var initials: [String] = []
    init(names: [String] = []) {
        for name in names where name.unicodeScalars.contains(where: { (0x3400...0x9fff).contains($0.value) }) {
            // Phrase-level corrections, not combinatorial readings of every character.
            let corrected = name.replacingOccurrences(of: "音乐", with: " yin yue ")
                .replacingOccurrences(of: "銀行", with: " yin hang ")
                .replacingOccurrences(of: "银行", with: " yin hang ")
            guard let latin = corrected.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) else { continue }
            let tokens = normalized(latin).split { !$0.isLetter && !$0.isNumber }.map(String.init)
            let joined = tokens.joined()
            let short = tokens.compactMap { $0.first }.map(String.init).joined()
            if !joined.isEmpty { full.append(joined) }
            if short.count >= 2 { initials.append(short) }
        }
        full = Array(Set(full)); initials = Array(Set(initials))
    }
    func matches(_ term: String) -> Bool {
        guard term.count >= 2, term.unicodeScalars.allSatisfy({ (97...122).contains($0.value) || (48...57).contains($0.value) }) else { return false }
        return full.contains { $0.contains(term) } || initials.contains { $0.hasPrefix(term) }
    }
}

struct Entry: Codable {
    let path: String
    let name: String
    let kind: FileKind
    let modified: Double
    let isFinderAlias: Bool
    let isSymbolicLink: Bool
    let searchAliases: [String]
    let searchName: String
    let searchPath: String
    var pinyin = ApplicationPinyin()
    // Derived query data is deliberately excluded from the persistent cache schema.
    enum CodingKeys: String, CodingKey {
        case path, name, kind, modified, isFinderAlias, isSymbolicLink, searchAliases, searchName, searchPath
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(FileKind.self, forKey: .kind)
        modified = try c.decode(Double.self, forKey: .modified)
        isFinderAlias = try c.decode(Bool.self, forKey: .isFinderAlias)
        isSymbolicLink = try c.decode(Bool.self, forKey: .isSymbolicLink)
        searchAliases = try c.decode([String].self, forKey: .searchAliases)
        searchName = try c.decode(String.self, forKey: .searchName)
        searchPath = try c.decode(String.self, forKey: .searchPath)
        if kind == .application { pinyin = ApplicationPinyin(names: [name]) }
    }
    init(path: String, directory: Bool, modified: Double = 0, isFinderAlias: Bool = false, isSymbolicLink: Bool = false) {
        self.path = path
        self.isFinderAlias = isFinderAlias && !isSymbolicLink
        self.isSymbolicLink = isSymbolicLink
        let url = URL(fileURLWithPath: path)
        // An application symlink is itself not a directory. Read only its target
        // metadata for classification; keep the entry path and never traverse it.
        var applicationURL = url
        var applicationDirectory = directory
        if isSymbolicLink && url.pathExtension.lowercased() == "app" {
            let target = url.resolvingSymlinksInPath()
            if target.pathExtension.lowercased() == "app",
               (try? target.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                applicationURL = target
                applicationDirectory = true
            }
        }
        kind = FileKind.classify(url, directory: applicationDirectory)
        if kind == .application {
            let bundle = Bundle(url: applicationURL)
            let localized = bundle?.localizedInfoDictionary
            name = (localized?["CFBundleDisplayName"] as? String) ?? (localized?["CFBundleName"] as? String) ?? (bundle?.infoDictionary?["CFBundleDisplayName"] as? String) ?? (bundle?.infoDictionary?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
            searchAliases = Array(Set([name, url.lastPathComponent, url.deletingPathExtension().lastPathComponent,
                bundle?.infoDictionary?["CFBundleDisplayName"] as? String ?? "",
                bundle?.infoDictionary?["CFBundleName"] as? String ?? ""].filter { !$0.isEmpty }.map(normalized)))
        } else {
            name = url.lastPathComponent; searchAliases = [normalized(name)]
        }
        self.modified = modified
        searchName = normalized(name)
        searchPath = normalized(path)
        if kind == .application { pinyin = ApplicationPinyin(names: [name]) }
    }
}
func extensionSet(_ text: String) -> Set<String> {
    Set(normalized(text).split(whereSeparator: { $0 == "," || $0 == "，" || $0.isWhitespace })
        .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.filter { !$0.isEmpty })
}

struct BlacklistFilter {
    let directories: [String]
    let extensions: Set<String>
    let keywords: [String]
    let excludeFinderAliases: Bool
    let excludeSymbolicLinks: Bool
    init(_ settings: Settings) {
        excludeFinderAliases = settings.usesBlacklist && settings.excludeFinderAliases == true
        excludeSymbolicLinks = settings.usesBlacklist && settings.excludeSymbolicLinks == true
        directories = settings.usesBlacklist ? settings.exclusions.filter { !$0.isEmpty }.map(expandedPath) : []
        extensions = settings.usesBlacklist ? extensionSet(settings.blockedExtensions ?? "") : []
        keywords = settings.usesBlacklist ? (settings.blockedKeywords ?? []).map { normalized($0.trimmingCharacters(in: .whitespacesAndNewlines)) }.filter { !$0.isEmpty } : []
    }
    func rejects(_ entry: Entry) -> Bool {
        if excludeFinderAliases && entry.isFinderAlias { return true }
        if excludeSymbolicLinks && entry.isSymbolicLink { return true }
        if directories.contains(where: { within(entry.path, $0) }) { return true }
        if entry.kind != .folder && extensions.contains(normalized(URL(fileURLWithPath: entry.path).pathExtension)) { return true }
        return keywords.contains { word in entry.searchAliases.contains { $0.contains(word) } }
    }
}

// macOS exposes some system apps through hidden links in /Applications.
// Recognize only those system-owned locations, not arbitrary hidden app links.
func isSystemApplicationLink(_ url: URL, symbolic: Bool) -> Bool {
    guard symbolic, url.deletingLastPathComponent().path == "/Applications",
          url.pathExtension.lowercased() == "app" else { return false }
    let target = url.resolvingSymlinksInPath()
    let systemRoots = ["/System/Applications", "/System/Cryptexes/App/System/Applications",
                       "/System/Volumes/Preboot/Cryptexes/App/System/Applications"]
    return systemRoots.contains { within(target.path, $0) }
        && target.pathExtension.lowercased() == "app"
        && (try? target.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
}

struct ScanResult {
    var entries: [Entry] = []
    var errors: [String] = []
    var cancelled = false
}

func scan(_ settings: Settings, cancelled: () -> Bool = { false }, progress: ([Entry], String) -> Void = { _, _ in }) -> ScanResult {
    var result = ScanResult()
    let fm = FileManager.default
    let roots = Array(Set(settings.searchRoots.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(expandedPath))).sorted { $0.count < $1.count }
    var selected: [String] = []
    for root in roots where !selected.contains(where: { within(root, $0) }) { selected.append(root) }
    let blacklist = BlacklistFilter(settings)
    let excluded = blacklist.directories
    var seen = Set<String>()
    let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey, .isHiddenKey, .isPackageKey, .contentModificationDateKey]
    func append(_ url: URL, _ values: URLResourceValues) {
        guard seen.insert(url.path).inserted else { return }
        let entry = Entry(path: url.path, directory: values.isDirectory == true, modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0, isFinderAlias: values.isAliasFile == true, isSymbolicLink: values.isSymbolicLink == true)
        if !blacklist.rejects(entry) { result.entries.append(entry) }
    }
    for root in selected {
        if cancelled() { result.cancelled = true; break }
        if excluded.contains(where: { within(root, $0) }) { continue }
        progress(result.entries, root)
        let url = URL(fileURLWithPath: root)
        do {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isDirectory == true else { result.errors.append("不是目录：\(root)"); continue }
            guard fm.isReadableFile(atPath: root) else { result.errors.append("不可读取：\(root)"); continue }
            append(url, values)
        } catch { result.errors.append("无法访问：\(root)"); continue }
        // Supplement only hidden system app entrances; keep native hidden-file traversal.
        if within("/Applications", root),
           !excluded.contains(where: { within("/Applications", $0) }),
           let entrances = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"),
                                                       includingPropertiesForKeys: keys) {
            for entrance in entrances {
                if cancelled() { result.cancelled = true; break }
                if let values = try? entrance.resourceValues(forKeys: Set(keys)),
                   values.isHidden == true,
                   isSystemApplicationLink(entrance, symbolic: values.isSymbolicLink == true) {
                    append(entrance, values)
                }
            }
        }
        let options: FileManager.DirectoryEnumerationOptions = settings.showHidden ? [.skipsPackageDescendants] : [.skipsPackageDescendants, .skipsHiddenFiles]
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: options, errorHandler: { u, _ in
            result.errors.append("无法读取：\(u.path)"); return true
        }) else { result.errors.append("无法遍历：\(root)"); continue }
        while let item = enumerator.nextObject() as? URL {
            if cancelled() { result.cancelled = true; break }
            if excluded.contains(where: { within(item.path, $0) }) { enumerator.skipDescendants(); continue }
            do {
                let values = try item.resourceValues(forKeys: Set(keys))
                // Do not follow links into a directory outside the selected scope.
                if values.isSymbolicLink == true { enumerator.skipDescendants() }
                append(item, values)
            } catch { result.errors.append("无法读取属性：\(item.path)") }
        }
        if result.cancelled { break }
    }
    return result
}

struct SearchResult { var entries: [Entry]; var total: Int }
func search(_ entries: [Entry], query: String, settings: Settings, cancelled: () -> Bool = { false }) -> SearchResult {
    let q = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !q.isEmpty, !cancelled() else { return SearchResult(entries: [], total: 0) }
    let terms = q.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    let extensions = extensionSet(settings.customExtensions)
    let blacklist = BlacklistFilter(settings)
    let roots = settings.searchRoots.map(expandedPath)
    let limit = max(1, settings.limit)
    // Worst result at the root: only the best N need to be retained and sorted.
    typealias Hit = (entry: Entry, score: Int)
    var heap: [Hit] = []; var total = 0
    var legacyTypes: [String: FileKind] = [:]
    func better(_ a: Hit, _ b: Hit) -> Bool {
        if settings.applicationsFirst == true, (a.entry.kind == .application) != (b.entry.kind == .application) {
            return a.entry.kind == .application
        }
        if a.score != b.score { return a.score < b.score }
        if settings.sortModified && a.entry.modified != b.entry.modified { return a.entry.modified > b.entry.modified }
        if a.entry.name != b.entry.name { return a.entry.name.localizedStandardCompare(b.entry.name) == .orderedAscending }
        return a.entry.path < b.entry.path
    }
    for (index, e) in entries.enumerated() {
        if index % 128 == 0 && cancelled() { return SearchResult(entries: [], total: 0) }
        let nameMatches = terms.allSatisfy { term in e.searchAliases.contains { $0.contains(term) } }
        let pathMatches = !nameMatches && settings.matchPath && terms.allSatisfy { term in e.searchPath.contains(term) || e.searchAliases.contains { $0.contains(term) } }
        let pinyinMatches = !nameMatches && !pathMatches && e.kind == .application && terms.allSatisfy { term in
            e.searchAliases.contains { $0.contains(term) } || e.pinyin.matches(term)
        }
        guard nameMatches || pathMatches || pinyinMatches else { continue }
        guard let root = roots.first(where: { within(e.path, $0) }), !blacklist.rejects(e) else { continue }
        if !settings.showHidden && e.path.dropFirst(root.count).split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
        if settings.usesWhitelist && !settings.allTypes {
            let ext = (e.path as NSString).pathExtension.lowercased()
            let directory = e.kind == .folder || e.kind == .application
            let extensionless = settings.includeExtensionless == true && !directory && ext.isEmpty
            var included: Bool
            if let legacy = settings.legacyKinds {
                let key = (directory ? "d:" : "f:") + ext
                let kind: FileKind
                if let known = legacyTypes[key] { kind = known }
                else { kind = FileKind.classify(URL(fileURLWithPath: e.path), directory: directory, legacy: true); legacyTypes[key] = kind }
                included = legacy.contains(kind)
            } else { included = settings.kinds.contains(e.kind) || (e.kind == .text && settings.kinds.contains(.document)) }
            guard included || extensionless || extensions.contains(ext) else { continue }
        }
        total += 1
        let score = e.searchAliases.contains(q) ? 0 : (e.searchAliases.contains { $0.hasPrefix(q) } ? 1 : (nameMatches ? 2 : (pathMatches ? 3 : 4)))
        let hit: Hit = (e, score)
        if heap.count < limit {
            heap.append(hit)
            var child = heap.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard better(heap[parent], heap[child]) else { break }
                heap.swapAt(parent, child); child = parent
            }
        } else if better(hit, heap[0]) {
            heap[0] = hit
            var parent = 0
            while parent * 2 + 1 < heap.count {
                var child = parent * 2 + 1
                if child + 1 < heap.count && better(heap[child], heap[child + 1]) { child += 1 }
                guard better(heap[parent], heap[child]) else { break }
                heap.swapAt(parent, child); parent = child
            }
        }
    }
    guard !cancelled() else { return SearchResult(entries: [], total: 0) }
    return SearchResult(entries: heap.sorted(by: better).map { $0.entry }, total: total)
}

// Only scan-affecting settings invalidate the on-disk snapshot. Search-time
// filters (types, keywords, ordering) are still applied to every cached query.
struct IndexScope: Codable, Equatable {
    let roots: [String]
    let hidden: Bool
    let excluded: [String]
    let extensions: String
    let keywords: [String]
    let aliases: Bool
    let links: Bool
    let languages: [String]
    init(_ settings: Settings) {
        roots = Array(Set(settings.searchRoots.map(expandedPath))).sorted()
        hidden = settings.showHidden
        excluded = settings.usesBlacklist ? settings.exclusions.map(expandedPath).sorted() : []
        extensions = settings.usesBlacklist ? settings.blockedExtensions ?? "" : ""
        keywords = settings.usesBlacklist ? (settings.blockedKeywords ?? []).sorted() : []
        aliases = settings.usesBlacklist && (settings.excludeFinderAliases ?? false)
        links = settings.usesBlacklist && (settings.excludeSymbolicLinks ?? false)
        languages = Locale.preferredLanguages
    }
}

struct IndexSnapshot: Codable {
    let version: Int
    let eventID: UInt64?
    let calibrated: Date?
    let scope: IndexScope
    let updated: Date
    let entries: [Entry]
    static func load(from url: URL, settings: Settings) -> IndexSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? PropertyListDecoder().decode(Self.self, from: data),
              snapshot.version == 2, snapshot.scope == IndexScope(settings) else { return nil }
        return snapshot
    }
    static func save(_ entries: [Entry], settings: Settings, updated: Date, eventID: UInt64? = nil, calibrated: Date? = nil, to url: URL) throws {
        let snapshot = Self(version: 2, eventID: eventID, calibrated: calibrated, scope: IndexScope(settings), updated: updated, entries: entries)
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try encoder.encode(snapshot).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Saving presentation preferences must not restart filesystem work.
struct SettingsUpdate {
    let scopeChanged: Bool
    let modeChanged: Bool
    let listenerChanged: Bool
    let queryChanged: Bool
    let shortcutChanged: Bool
    var needsScan: Bool { nativeMode && (scopeChanged || enableListener || modeChanged) }
    private let nativeMode: Bool
    private let enableListener: Bool
    init(from old: Settings, to new: Settings) {
        modeChanged = old.effectiveSearchMode != new.effectiveSearchMode
        nativeMode = new.effectiveSearchMode == .native
        scopeChanged = IndexScope(old) != IndexScope(new)
        listenerChanged = old.autoRefresh != new.autoRefresh
        enableListener = !old.autoRefresh && new.autoRefresh
        shortcutChanged = old.hotKey != new.hotKey
        queryChanged = modeChanged || old.pinnedItems != new.pinnedItems || scopeChanged || old.usesWhitelist != new.usesWhitelist
            || old.kinds != new.kinds || old.legacyKinds != new.legacyKinds
            || old.allTypes != new.allTypes || old.includeExtensionless != new.includeExtensionless
            || extensionSet(old.customExtensions) != extensionSet(new.customExtensions)
            || old.matchPath != new.matchPath || old.sortModified != new.sortModified
            || (old.applicationsFirst == true) != (new.applicationsFirst == true)
            || old.limit != new.limit || (old.searchSystemSettings != false) != (new.searchSystemSettings != false)
            || (old.searchContacts == true) != (new.searchContacts == true)
    }
}


/// Explicit bindings never expand the filesystem scan scope.
struct PinnedItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var term: String
    var target: String
    var displayName: String = ""
    var bookmark: Data? = nil
    static func key(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased()
    }
    func matchesPinyin(_ query: String) -> Bool {
        let query = Self.key(query)
        guard query.count >= 2,
              query.unicodeScalars.allSatisfy({ (97...122).contains($0.value) || (48...57).contains($0.value) }) else { return false }
        // Reuse transliteration, not applications' substring/prefix matching:
        // a pin still requires a complete term, full pinyin or initials.
        let aliases = ApplicationPinyin(names: [term])
        return aliases.full.contains(query) || aliases.initials.contains(query)
    }
    static func targetURL(_ value: String) throws -> URL {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("/") || text == "~" || text.hasPrefix("~/") {
            let url = URL(fileURLWithPath: (text as NSString).expandingTildeInPath).standardizedFileURL
            return URL(fileURLWithPath: expandedPath(url.deletingLastPathComponent().path)).appendingPathComponent(url.lastPathComponent)
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else {
            throw PinError("请输入绝对路径、~/ 路径或完整的 http(s) 网页地址。")
        }
        if scheme == "file", url.host == nil || url.host == "" || url.host == "localhost" {
            return try targetURL(url.path)
        }
        guard ["https", "http"].contains(scheme), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else {
            throw PinError("仅支持本地文件路径和不含账号密码的 http(s) 网页地址。")
        }
        return url
    }
    func resolve() throws -> ResolvedPin {
        var url = try Self.targetURL(target)
        if url.isFileURL, let bookmark {
            var stale = false
            // Do not fall back to a potentially unrelated replacement at the old path.
            guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) else {
                throw PinError("目标已失效，请编辑并重新确认路径。")
            }
            url = resolved
        }
        var entry: Entry?
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path), FileManager.default.isReadableFile(atPath: url.path) else {
                throw PinError("目标不存在或没有读取权限。")
            }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isAliasFileKey, .isSymbolicLinkKey])
            entry = Entry(path: url.path, directory: values.isDirectory == true, isFinderAlias: values.isAliasFile == true, isSymbolicLink: values.isSymbolicLink == true)
        }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ResolvedPin(url: url, entry: entry, name: name.isEmpty ? (entry?.name ?? url.host ?? target) : name)
    }
    static func make(term: String, target: String, name: String, id: UUID = UUID(), others: [PinnedItem]) throws -> PinnedItem {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !term.contains("\n"), !term.contains("\r") else { throw PinError("请填写单行检索词。") }
        guard !others.contains(where: { $0.id != id && key($0.term) == key(term) }) else { throw PinError("这个检索词已存在，请编辑原条目或换一个词。") }
        let url = try targetURL(target)
        var item = PinnedItem(id: id, term: term, target: url.isFileURL ? url.path : url.absoluteString, displayName: name.trimmingCharacters(in: .whitespacesAndNewlines))
        _ = try item.resolve()
        if url.isFileURL { item.bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }
        return item
    }
}
struct PinError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
struct ResolvedPin {
    let url: URL
    let entry: Entry?
    let name: String
}


/// Ephemeral contact data: never Codable and never sent to a filesystem engine.
struct ContactPhone {
    let contactID: String
    let numberID: String
    let name: String
    let label: String
    let rawNumber: String
    let phoneticNames: [String]
    let copyNumber: String?
    let extensionNumber: String?
    var hasExtension: Bool { extensionNumber != nil }
    var identity: String { contactID + "/" + numberID }
    var subtitle: String {
        [label.isEmpty ? "电话" : label, rawNumber, hasExtension ? "仅复制主号" : (copyNumber == nil ? "特殊号码，请回车查看" : "")]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var url: URL? {
        // Encode the identifier as one component (macOS IDs may include :ABPerson).
        guard let id = contactID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "addressbook://" + id)
    }
    init(contactID: String, numberID: String, name: String, label: String, rawNumber: String, phoneticNames: [String] = []) {
        self.contactID = contactID; self.numberID = numberID; self.name = name; self.label = label
        self.rawNumber = rawNumber; self.phoneticNames = phoneticNames
        let parsed = Self.parse(rawNumber)
        copyNumber = parsed.number; extensionNumber = parsed.ext
    }
    private static let extensionPattern = try! NSRegularExpression(pattern: #"(?i)(?:;ext=|(?:extension|ext\.?|分机|转)\s*[:：]?|[x#])\s*([0-9]+)\s*$"#)
    private static func parse(_ raw: String) -> (number: String?, ext: String?) {
        var main = raw.folding(options: [.widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var ext: String?
        if let match = extensionPattern.firstMatch(in: main, range: NSRange(main.startIndex..., in: main)),
           let range = Range(match.range, in: main), let digits = Range(match.range(at: 1), in: main) {
            ext = String(main[digits]); main = String(main[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let allowed = CharacterSet(charactersIn: "0123456789+().-‐‑–—").union(.whitespacesAndNewlines)
        guard !main.isEmpty, main.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              main.filter({ $0 == "+" }).count <= 1, !main.contains("+") || main.hasPrefix("+") else { return (nil, ext) }
        let compact = main.filter { $0 == "+" || ($0 >= "0" && $0 <= "9") }
        var digits = String(compact.filter { $0 != "+" })
        let national: String?
        if compact.hasPrefix("+86") { national = String(digits.dropFirst(2)) }
        else if compact.hasPrefix("0086") { national = String(digits.dropFirst(4)) }
        else { national = nil }
        // Only strip explicit mainland country codes on plausible full numbers.
        // Never guess from a bare 86 prefix, or infer/rewrite another country's code.
        if let national, (10...12).contains(national.count) { digits = national }
        return (digits.isEmpty ? nil : digits, ext)
    }
}

struct ContactSearchIndex {
    private var byName: [String: [ContactPhone]] = [:]
    private var byPinyin: [String: [ContactPhone]] = [:]
    init(_ phones: [ContactPhone] = []) {
        var seen = Set<String>()
        var aliases: [String: [String]] = [:]
        for phone in phones {
            let duplicateKey = phone.contactID + ":" + (phone.copyNumber ?? phone.rawNumber) + ":" + (phone.extensionNumber ?? "")
            guard !Self.nameKey(phone.name).isEmpty, seen.insert(duplicateKey).inserted else { continue }
            byName[Self.nameKey(phone.name), default: []].append(phone)
            if aliases[phone.contactID] == nil {
                let names = phone.phoneticNames.isEmpty ? [phone.name] : phone.phoneticNames
                aliases[phone.contactID] = Array(Set(names.compactMap { name in
                    guard phone.phoneticNames.isEmpty ? name.unicodeScalars.contains(where: { (0x3400...0x9fff).contains($0.value) }) : true,
                          let latin = name.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) else { return nil }
                    let key = Self.pinyinKey(latin)
                    return key.isEmpty ? nil : key
                }))
            }
            for key in aliases[phone.contactID] ?? [] { byPinyin[key, default: []].append(phone) }
        }
    }
    private static func nameKey(_ text: String) -> String {
        normalized(text).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    private static func pinyinKey(_ text: String) -> String {
        let key = normalized(text).filter { !$0.isWhitespace }
        return !key.isEmpty && key.utf8.allSatisfy { (97...122).contains($0) } ? key : ""
    }
    func search(_ query: String) -> [ContactPhone] {
        let literal = byName[Self.nameKey(query)] ?? []
        let pinyin = byPinyin[Self.pinyinKey(query)] ?? []
        var seen = Set<String>()
        return (literal + pinyin).filter { seen.insert($0.identity).inserted }
    }
}
