import Foundation
@main struct SearchDiagnosticsTests {
 static func main() throws {
    let dir = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("sample.txt")
    try Data("sample".utf8).write(to: file)
    var s = Settings(); s.roots = [dir.path]; s.whitelistEnabled = true; s.allTypes = true
    let e = Entry(path: expandedPath(file.path), directory: false)
    let ok = diagnoseFile(path: file.path, query: "sample", settings: s, entries: [e], indexing: false, errors: [])
    precondition(ok.contains("包含此对象") && ok.contains("位于当前候选"))
    s.blacklistEnabled = true; s.blockedKeywords = ["sample"]
    precondition(diagnoseFile(path: file.path, query: "sample", settings: s, entries: [e], indexing: false, errors: []).contains("关键词：sample"))
    s.blacklistEnabled = false; s.roots = [dir.appendingPathComponent("elsewhere").path]
    precondition(diagnoseFile(path: file.path, query: "", settings: s, entries: [], indexing: true, errors: []).contains("不在当前扫描目录"))
    precondition(diagnoseFile(path: file.path + "missing", query: "", settings: s, entries: [], indexing: false, errors: []).contains("无法读取对象属性"))
    s.roots = [dir.path]; s.allTypes = false; s.kinds = [.application]; s.legacyKinds = nil; s.customExtensions = ""
    precondition(diagnoseFile(path: file.path, query: "", settings: s, entries: [], indexing: false, errors: []).contains("类型排除"))
    let data = try Data(contentsOf: file)
    precondition(data == Data("sample".utf8))
    print("PASS: diagnostics inclusion, keyword exclusion, range, absent path, type exclusion and read-only file content")
 }
}
