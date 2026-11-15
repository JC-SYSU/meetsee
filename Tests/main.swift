import Foundation
var s = Settings(); s.roots = ["/test"]; s.allTypes = true
let entries = [Entry(path: "/test/超声18", directory: true), Entry(path: "/test/超声背景.png", directory: false), Entry(path: "/test/03 AI赋能临床研究设计及CRF.pptx", directory: false), Entry(path: "/test/fair.txt", directory: false), Entry(path: "/test/超声18/notes.txt", directory: false)]
var checks = 0
func check(_ ok: Bool, _ label: String) { checks += 1; if !ok { fatalError(label) } }
check(search(entries, query: "超声18", settings: s).total == 1, "Chinese exact")
check(search(entries, query: "超声", settings: s).total == 2, "Chinese substring")
check(search(entries, query: "临床 ai", settings: s).total == 1, "mixed reversed tokens")
check(search(entries, query: "ＡＩ", settings: s).total == 2, "width folding and true substring")
check(search(entries, query: "   ", settings: s).total == 0, "empty query")
s.matchPath = true
check(search(entries, query: "超声18 notes", settings: s).total == 1, "path tokens")
s.exclusions = ["/test/超声18"]
check(search(entries, query: "notes", settings: s).total == 0, "exclusion")
check(!within("/test-extra/file", "/test"), "path boundary")
s.exclusions = []; s.matchPath = false; s.allTypes = false; s.kinds = [.folder]
check(search(entries, query: "超声", settings: s).total == 1, "category")
s.customExtensions = ".png"
check(search(entries, query: "超声", settings: s).total == 2, "custom extension")
s.limit = 1
check(search(entries, query: "超声", settings: s).entries.count == 1 && search(entries, query: "超声", settings: s).total == 2, "limit preserves total")
let fm = FileManager.default
try fm.createDirectory(atPath: CommandLine.arguments[1], withIntermediateDirectories: true)
let fixture = expandedPath(CommandLine.arguments[1])
try fm.createDirectory(atPath: fixture + "/超声18", withIntermediateDirectories: true)
try Data().write(to: URL(fileURLWithPath: fixture + "/超声18/new.txt"))
s = Settings(); s.roots = [fixture, fixture + "/超声18"]; s.allTypes = true
var scan1 = scan(s)
check(scan1.entries.filter { $0.name == "new.txt" }.count == 1, "overlapping roots deduplicate")
try fm.moveItem(atPath: fixture + "/超声18/new.txt", toPath: fixture + "/超声18/renamed.txt")
scan1 = scan(s)
check(search(scan1.entries, query: "new.txt", settings: s).total == 0 && search(scan1.entries, query: "renamed.txt", settings: s).total == 1, "rename refresh")
try fm.removeItem(atPath: fixture + "/超声18/renamed.txt")
check(search(scan(s).entries, query: "renamed.txt", settings: s).total == 0, "delete refresh")
check(scan(s, cancelled: { true }).cancelled, "cancellation")
print("PASS: \(checks) checks")
let unicode = [Entry(path: "/test/Cafe\u{301}.txt", directory: false)]
s = Settings(); s.roots = ["/test"]; s.allTypes = true
check(search(unicode, query: "CAFÉ", settings: s).total == 1, "unicode normalization")
check(search(entries, query: "18 超声", settings: s).total == 1, "Chinese reordered tokens")
s = Settings(); s.roots = [fixture]; s.allTypes = true
try Data().write(to: URL(fileURLWithPath: fixture + "/.hidden.txt"))
check(!scan(s).entries.contains { $0.name == ".hidden.txt" }, "hidden excluded")
s.showHidden = true
check(scan(s).entries.contains { $0.name == ".hidden.txt" }, "hidden included")
s.exclusions = [fixture + "/超声18"]
check(!scan(s).entries.contains { within($0.path, fixture + "/超声18") }, "scan excludes subtree")
let encoded = try JSONEncoder().encode(s)
let decoded = try JSONDecoder().decode(Settings.self, from: encoded)
check(decoded.roots == s.roots && decoded.exclusions == s.exclusions && decoded.showHidden, "settings persistence")
print("PASS: \(checks) total checks")

var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
legacy["fallback"] = true
let migrated = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: legacy))
check(migrated.roots == s.roots, "legacy web setting does not reset local scopes")
let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(migrated)) as! [String: Any]
check(saved["fallback"] == nil, "web setting removed from persisted schema")
print("PASS: \(checks) total checks including local-only migration")

check(decoded.effectiveFontName == "Maple Mono NF CN", "default font for old settings")
var fontSettings = decoded; fontSettings.fontName = "Menlo"
check(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(fontSettings)).effectiveFontName == "Menlo", "custom font persistence")
let appRoot = fixture + "/Font Book.app"
try fm.createDirectory(atPath: appRoot + "/Contents", withIntermediateDirectories: true)
let info: [String: Any] = ["CFBundleIdentifier": "local.quickfind.fixture", "CFBundleName": "Font Book", "CFBundleDisplayName": "字体册", "CFBundlePackageType": "APPL"]
try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: URL(fileURLWithPath: appRoot + "/Contents/Info.plist"))
let apps = [Entry(path: appRoot, directory: true)]
var appSettings = Settings(); appSettings.roots = [fixture]
check(search(apps, query: "字体册", settings: appSettings).total == 1, "localized application name")
check(search(apps, query: "font book", settings: appSettings).total == 1, "original application name")
check(search(apps, query: "字体 book", settings: appSettings).total == 1, "mixed application aliases")
appSettings.kinds = [.folder]
check(search(apps, query: "字体册", settings: appSettings).total == 0, "application filter respected")
print("PASS: \(checks) total checks including fonts and application aliases")

check(Settings().hotKey == 3, "default Command Space shortcut")
print("PASS: \(checks) total checks including default shortcut")

let bareEntries = [Entry(path: "/test/README", directory: false), Entry(path: "/test/README-dir", directory: true), Entry(path: "/test/README.bin", directory: false), Entry(path: "/test/.README", directory: false)]
var bareSettings = Settings(); bareSettings.roots = ["/test"]; bareSettings.kinds = [.application]
check(search(bareEntries, query: "README", settings: bareSettings).total == 0, "extensionless opt-in defaults off")
bareSettings.includeExtensionless = true
check(search(bareEntries, query: "README", settings: bareSettings).entries.map { $0.path } == ["/test/README"], "extensionless includes files only and respects hidden policy")
bareSettings.exclusions = ["/test/README"]
check(search(bareEntries, query: "README", settings: bareSettings).total == 0, "extensionless respects exclusions")
let bareDecoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(bareSettings))
check(bareDecoded.includeExtensionless == true, "extensionless option persists")
check(decoded.includeExtensionless == nil, "old settings keep extensionless disabled")
print("PASS: \(checks) total checks including extensionless files")

var rules = Settings(); rules.roots = ["/test"]; rules.kinds = [.image]
check(rules.usesWhitelist && !rules.usesBlacklist, "new defaults whitelist on blacklist off")
let ruleEntries = [Entry(path: "/test/report.PNG", directory: false), Entry(path: "/test/report.pdf", directory: false), Entry(path: "/test/secret/REPORT.png", directory: false), Entry(path: "/test/report.tmp", directory: false)]
rules.customExtensions = " .PDF， pdf "
check(search(ruleEntries, query: "report", settings: rules).total == 3, "white types OR extensions within directories")
rules.blacklistEnabled = true; rules.blockedExtensions = " .PNG "
check(search(ruleEntries, query: "report", settings: rules).entries.map { $0.name } == ["report.pdf"], "black extension beats white type ignoring case")
rules.blockedExtensions = ""; rules.blockedKeywords = ["ＲＥＰＯＲＴ", "  "]
check(search(ruleEntries, query: "report", settings: rules).total == 0, "black normalized keyword wins")
rules.blockedKeywords = ["secret"]
check(search(ruleEntries, query: "report", settings: rules).total == 3, "black keywords match names not parent paths")
rules.exclusions = ["/test/secret"]
check(search(ruleEntries, query: "report", settings: rules).total == 2, "black directory excludes descendants")
rules.blacklistEnabled = false
check(search(ruleEntries, query: "report", settings: rules).total == 3, "disabled blacklist retains but ignores all rules")
let home = expandedPath("~")
let homeEntries = [Entry(path: home + "/report.tmp", directory: false), Entry(path: "/Applications/report.app", directory: true)]
rules.whitelistEnabled = false
check(rules.searchRoots == ["~"], "disabled whitelist uses home scope")
check(search(homeEntries, query: "report", settings: rules).entries.map { $0.path } == [home + "/report.tmp"], "whitelist off removes type restriction but never leaves home")
rules.blacklistEnabled = true; rules.blockedExtensions = "tmp"
check(search(homeEntries, query: "report", settings: rules).total == 0, "blacklist applies with whitelist off")
rules.whitelistEnabled = true; rules.roots = []
check(search(homeEntries, query: "report", settings: rules).total == 0, "empty enabled whitelist does not expand scope")
let rulesSaved = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(rules))
check(rulesSaved.whitelistEnabled == true && rulesSaved.blacklistEnabled == true && rulesSaved.blockedExtensions == "tmp", "rule toggles persist")
check(migrated.usesWhitelist && migrated.usesBlacklist, "legacy nonempty exclusions preserved on migration")
var scanRules = Settings(); scanRules.roots = [fixture]; scanRules.blacklistEnabled = true; scanRules.blockedExtensions = "tmp"
try Data().write(to: URL(fileURLWithPath: fixture + "/blocked.tmp"))
check(!scan(scanRules).entries.contains { $0.name == "blocked.tmp" }, "scan enforces black extensions")
scanRules.blacklistEnabled = false
check(scan(scanRules).entries.contains { $0.name == "blocked.tmp" }, "rescan restores items after blacklist disabled")
print("PASS: \(checks) total checks including whitelist/blacklist")

check(Settings().effectiveHighlightStyle == .mist, "default highlight is mist")
check(migrated.effectiveHighlightStyle == .mist, "legacy settings gain mist without migration write")
check(HighlightStyle.selectable == [.mist, .pearl, .marker], "graphite stays hidden from the theme picker")
for style in HighlightStyle.selectable {
    var styled = rules; styled.highlightStyle = style.rawValue
    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(styled))
    check(decoded.effectiveHighlightStyle == style && decoded.roots == rules.roots && decoded.kinds == rules.kinds, "style persists without changing search rules")
}
var legacyGraphite = Settings(); legacyGraphite.highlightStyle = "graphite"
check(legacyGraphite.effectiveHighlightStyle == .mist, "hidden graphite falls back to mist")
var unknownStyle = Settings(); unknownStyle.highlightStyle = "future-style"
check(unknownStyle.effectiveHighlightStyle == .mist, "unknown style safely falls back")
print("PASS: \(checks) total checks including highlight styles")

let aliasRoot = URL(fileURLWithPath: fixture + "/link-tests")
try fm.createDirectory(at: aliasRoot, withIntermediateDirectories: true)
let original = aliasRoot.appendingPathComponent("原文件.txt")
try Data("fixture".utf8).write(to: original)
let aliasURL = aliasRoot.appendingPathComponent("无后缀替身")
let bookmark = try original.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
try URL.writeBookmarkData(bookmark, to: aliasURL)
let linkURL = aliasRoot.appendingPathComponent("符号链接.txt")
try fm.createSymbolicLink(at: linkURL, withDestinationURL: original)
var linkSettings = Settings(); linkSettings.roots = [aliasRoot.path]; linkSettings.allTypes = true; linkSettings.blacklistEnabled = true
let allLinks = scan(linkSettings)
check(allLinks.errors.isEmpty, "real alias fixture readable")
check(allLinks.entries.first { $0.path == aliasURL.path }?.isFinderAlias == true, "real Finder alias detected without extension")
check(allLinks.entries.first { $0.path == linkURL.path }?.isSymbolicLink == true, "real symlink detected")
check(allLinks.entries.first { $0.path == linkURL.path }?.isFinderAlias == false, "symlink never conflated with Finder alias")
linkSettings.excludeFinderAliases = true
let aliasesExcluded = scan(linkSettings)
check(!aliasesExcluded.entries.contains { $0.path == aliasURL.path } && aliasesExcluded.entries.contains { $0.path == linkURL.path }, "exclude aliases independently")
check(search(allLinks.entries, query: "无后缀", settings: linkSettings).total == 0, "query filters previously indexed aliases")
linkSettings.excludeFinderAliases = false; linkSettings.excludeSymbolicLinks = true
let linksExcluded = scan(linkSettings)
check(linksExcluded.entries.contains { $0.path == aliasURL.path } && !linksExcluded.entries.contains { $0.path == linkURL.path }, "exclude symlinks independently")
linkSettings.excludeFinderAliases = true
let bothExcluded = scan(linkSettings)
check(bothExcluded.entries.contains { $0.path == original.path } && bothExcluded.entries.count == 2, "original and root remain when both links excluded")
let restoredLinks = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(linkSettings))
check(restoredLinks.excludeFinderAliases == true && restoredLinks.excludeSymbolicLinks == true, "link options persist")
linkSettings.blacklistEnabled = false
check(scan(linkSettings).entries.count == allLinks.entries.count, "disabled blacklist restores links")
check(migrated.excludeFinderAliases != true && migrated.excludeSymbolicLinks != true, "legacy settings do not silently hide links")
print("PASS: \(checks) total checks including Finder aliases and symlinks")

var sizeSettings = Settings()
check(sizeSettings.effectiveWindowWidth == 720 && sizeSettings.effectiveVisibleRows == 5, "window defaults medium and five rows")
check(migrated.effectiveWindowWidth == 720 && migrated.effectiveVisibleRows == 5, "legacy window defaults")
for (key, width) in [("narrow", 600.0), ("medium", 720.0), ("wide", 840.0)] {
    sizeSettings.windowWidth = key
    check(sizeSettings.effectiveWindowWidth == width, "window width " + key)
}
for rows in 3...8 {
    sizeSettings.visibleRows = rows
    let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(sizeSettings))
    check(restored.effectiveVisibleRows == rows && restored.windowWidth == "wide", "window settings persist")
}
let many = (0..<60).map { Entry(path: expandedPath("/tmp") + "/example-\($0).txt", directory: false) }
sizeSettings.kinds = [.text]; sizeSettings.roots = ["/tmp"]
for limit in Settings.candidateLimits {
    sizeSettings.limit = limit
    let result = search(many, query: "example", settings: sizeSettings)
    check(result.entries.count == limit && result.total == 60, "candidate cap preserves total")
}
for legacy in [40, 80, 150] {
    sizeSettings.limit = legacy
    check(sizeSettings.effectiveCandidateLimit == 50, "legacy cap migrates to fifty")
}
print("PASS: \(checks) total checks including window sizing and candidate limits")

check(Settings().effectiveWhiteOverlayOpacity == 0 && migrated.effectiveWhiteOverlayOpacity == 0, "white overlay default and migration")
for step in 0...10 {
    var overlay = Settings(); overlay.whiteOverlayOpacity = Double(step) / 10
    let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(overlay))
    check(restored.effectiveWhiteOverlayOpacity == Double(step) / 10, "overlay step persists")
}
print("PASS: \(checks) total checks including white overlay")

var modern = Settings(); modern.roots = ["/test"]; modern.kinds = [.document]
let categoryEntries = ["note.txt", "table.xlsx", "setup.json", "music.flac", "movie.mkv", "code.py"].map { Entry(path: "/test/" + $0, directory: false) }
check(search(categoryEntries, query: ".", settings: modern).entries.count == 2, "documents include text but not code or media")
for (ext, kind) in [("flac", FileKind.audio), ("mkv", .video), ("json", .script), ("iso", .archive)] {
    check(FileKind.classify(URL(fileURLWithPath: "/test/sample." + ext), directory: false) == kind, "new category " + ext)
}
for oldKinds: Set<FileKind> in [[.document], [.text], [.other], [.script], [.document, .text]] {
    var old = Settings(); old.categoryVersion = nil; old.kinds = oldKinds; old.migrateCategories()
    check(categoryEntries.allSatisfy { old.includesKind($0) == oldKinds.contains(FileKind.classify(URL(fileURLWithPath: $0.path), directory: false, legacy: true)) }, "migration preserves legacy inclusion exactly")
    let roundtrip = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(old))
    check(roundtrip.legacyKinds == oldKinds, "legacy selection persists")
}
var tint = Settings(); tint.glassTintStrength = 0.7
check(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(tint)).effectiveGlassTintStrength == 0.7, "tint strength persists")
print("PASS: \(checks) total checks including categories and tint")

// Safari-style system application entry: classify the target, retain the scoped link.
let appTarget = URL(fileURLWithPath: fixture + "/external/SampleBrowser.app")
try fm.createDirectory(at: appTarget.appendingPathComponent("Contents"), withIntermediateDirectories: true)
let appInfo: [String: Any] = ["CFBundleName": "Sample Browser", "CFBundleIdentifier": "test.sample.browser", "CFBundlePackageType": "APPL"]
try PropertyListSerialization.data(fromPropertyList: appInfo, format: .xml, options: 0).write(to: appTarget.appendingPathComponent("Contents/Info.plist"))
let appLink = aliasRoot.appendingPathComponent("Browser.app")
try fm.createSymbolicLink(at: appLink, withDestinationURL: appTarget)
let brokenApp = aliasRoot.appendingPathComponent("Broken.app")
try fm.createSymbolicLink(at: brokenApp, withDestinationURL: aliasRoot.appendingPathComponent("Missing.app"))
var appLinkSettings = Settings(); appLinkSettings.roots = [aliasRoot.path]
appLinkSettings.kinds = [.application]; appLinkSettings.blacklistEnabled = true
appLinkSettings.excludeFinderAliases = true; appLinkSettings.excludeSymbolicLinks = false
let scannedLinks = scan(appLinkSettings)
let browser = scannedLinks.entries.first { $0.path == appLink.path }!
check(browser.kind == .application && browser.isSymbolicLink && !browser.isFinderAlias, "application symlink retains identity but gets target application type")
check(search(scannedLinks.entries, query: "sample browser", settings: appLinkSettings).total == 1, "application symlink searches target bundle name within original scope")
appLinkSettings.legacyKinds = [.application]
check(search(scannedLinks.entries, query: "browser", settings: appLinkSettings).entries.first?.path == appLink.path, "application symlink works with legacy type whitelist")
check(!scannedLinks.entries.contains { $0.path.hasPrefix(appTarget.path) || $0.path.hasPrefix(appLink.path + "/") }, "application target contents never traversed")
check(scannedLinks.entries.first { $0.path == brokenApp.path }?.kind != .application, "broken app symlink not classified as application")
appLinkSettings.excludeSymbolicLinks = true
check(search(scannedLinks.entries, query: "browser", settings: appLinkSettings).total == 0, "explicit symlink exclusion still hides linked applications")
print("PASS: application symlink classification, aliases, scope, legacy filter and no traversal")

let hiddenDirectory = aliasRoot.appendingPathComponent(".private")
try fm.createDirectory(at: hiddenDirectory, withIntermediateDirectories: true)
try Data().write(to: hiddenDirectory.appendingPathComponent("secret.txt"))
let hiddenAppLink = aliasRoot.appendingPathComponent("HiddenBrowser.app")
try fm.createSymbolicLink(at: hiddenAppLink, withDestinationURL: appTarget)
var hiddenURL = hiddenAppLink
var hiddenValues = URLResourceValues(); hiddenValues.isHidden = true
try hiddenURL.setResourceValues(hiddenValues)
appLinkSettings.excludeSymbolicLinks = false
let hiddenScan = scan(appLinkSettings)
check(!hiddenScan.entries.contains { $0.path == hiddenAppLink.path || $0.path.hasPrefix(hiddenDirectory.path) }, "ordinary hidden app links and hidden subtrees remain excluded")
appLinkSettings.showHidden = true
check(scan(appLinkSettings).entries.contains { $0.path == hiddenAppLink.path }, "explicit hidden option still includes ordinary hidden links")
check(!isSystemApplicationLink(appLink, symbolic: true), "user-created app links do not receive system hidden exemption")
print("PASS: hidden flags and hidden subtrees remain respected")
