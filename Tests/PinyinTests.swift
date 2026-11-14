import Foundation
@main struct PinyinTests {
 static func main() throws {
    var settings = Settings(); settings.roots = ["/test"]; settings.allTypes = true
    let apps = ["通讯录", "字体册", "微信", "网易云音乐", "重庆", "银行"].map { Entry(path: "/test/\($0).app", directory: true) }
    for (q, name) in [("tongxunlu", "通讯录"), ("txl", "通讯录"), ("ztc", "字体册"), ("wx", "微信"), ("wangyiyunyinyue", "网易云音乐"), ("wyyyy", "网易云音乐"), ("chongqing", "重庆"), ("yinhang", "银行"), ("wei 信", "微信")] {
        precondition(search(apps, query: q, settings: settings).entries.contains { $0.name == name }, q)
    }
    let file = Entry(path: "/test/微信.txt", directory: false)
    let folder = Entry(path: "/test/微信", directory: true)
    precondition(search([file, folder], query: "weixin", settings: settings).total == 0)
    precondition(search(apps, query: "w", settings: settings).total == 0)
    settings.blacklistEnabled = true; settings.blockedKeywords = ["weixin", "wx"]
    precondition(search(apps, query: "wx", settings: settings).total == 1)
    settings.blockedKeywords = ["微信"]
    precondition(search(apps, query: "wx", settings: settings).total == 0)
    settings.blacklistEnabled = false
    let literal = Entry(path: "/test/wx.txt", directory: false)
    precondition(search(apps + [literal], query: "wx", settings: settings).entries.first!.path == literal.path)
    let data = try JSONEncoder().encode(apps)
    precondition(!String(data: data, encoding: .utf8)!.contains("pinyin"))
    let restored = try JSONDecoder().decode([Entry].self, from: data)
    precondition(search(restored, query: "txl", settings: settings).total == 1)
    precondition(mergeSettings(SearchResult(entries: [], total: 0), pages: SettingsDestination.catalog, query: "jianpan", settings: settings).total == 0)
    print("PASS: application-only pinyin/full/initial/mixed matching, phrase corrections, literal ranking, blacklist isolation, cache regeneration, no settings pinyin")
 }
}
