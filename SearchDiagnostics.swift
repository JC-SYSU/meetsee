import Foundation

func diagnoseFile(path: String, query: String, settings: Settings, entries: [Entry], indexing: Bool, errors: [String]) -> String {
    // Canonicalize parent aliases such as /var, but preserve the selected link itself.
    let suppliedPath = path
    let inputURL = URL(fileURLWithPath: path).standardizedFileURL
    let path = URL(fileURLWithPath: expandedPath(inputURL.deletingLastPathComponent().path)).appendingPathComponent(inputURL.lastPathComponent).path
    let url = URL(fileURLWithPath: path)
    var lines = ["对象：\(path)", "规则：当前已保存设置", settings.effectiveSearchMode == .lokii ? "模式：Lokii（原生索引已暂停）" : indexing ? "索引：正在扫描／校准，本报告为当前快照。" : "索引：当前内存快照。"]
    let values: URLResourceValues
    do { values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey, .isHiddenKey]) }
    catch { return (lines + ["无法读取对象属性：\(error.localizedDescription)", "这可能是路径不存在或访问受限，不能据此判定缺少全盘权限。"] ).joined(separator: "\n\n") }
    let entry = Entry(path: path, directory: values.isDirectory == true, isFinderAlias: values.isAliasFile == true && values.isSymbolicLink != true, isSymbolicLink: values.isSymbolicLink == true)
    lines.append(FileManager.default.isReadableFile(atPath: path) ? "对象当前可读；不代表历史后台扫描具有相同访问条件。" : "对象当前不可读；请核对系统权限与文件权限。")
    let roots = settings.searchRoots.map(expandedPath).filter { within(path, $0) }
    if roots.isEmpty { lines.append("范围：不在当前扫描目录内。") }
    else { lines.append("范围：位于 \(roots.joined(separator: "、")) 内。") }
    let filter = BlacklistFilter(settings)
    if filter.rejects(entry) {
        var reasons: [String] = []
        if filter.excludeFinderAliases && entry.isFinderAlias { reasons.append("Finder 替身") }
        if filter.excludeSymbolicLinks && entry.isSymbolicLink { reasons.append("符号链接") }
        reasons += filter.directories.filter { within(path, $0) }.map { "目录：" + $0 }
        if entry.kind != .folder && filter.extensions.contains(normalized(url.pathExtension)) { reasons.append("扩展名：" + url.pathExtension) }
        reasons += filter.keywords.filter { w in entry.searchAliases.contains { $0.contains(w) } }.map { "关键词：" + $0 }
        lines.append("黑名单排除：" + reasons.joined(separator: "；"))
    } else { lines.append("黑名单：未命中排除规则。") }
    if !roots.isEmpty {
        // Inspect only the selected path's ancestors, never traverse their contents.
        let root = roots.min(by: { $0.count < $1.count })!
        var ancestor = url
        while within(ancestor.path, root) && ancestor.path != root {
            if let v = try? ancestor.resourceValues(forKeys: [.isHiddenKey, .isPackageKey, .isSymbolicLinkKey]) {
                if !settings.showHidden && (v.isHidden == true || ancestor.lastPathComponent.hasPrefix(".")) && !isSystemApplicationLink(ancestor, symbolic: v.isSymbolicLink == true) {
                    lines.append("遍历限制：隐藏对象或祖先 \(ancestor.path)")
                }
                if ancestor.path != path && (v.isPackage == true || v.isSymbolicLink == true) {
                    lines.append("遍历限制：位于包或符号链接目录内部 \(ancestor.path)")
                }
            }
            ancestor.deleteLastPathComponent()
        }
    }
    // The production matcher is authoritative for types and all query-time rules.
    let eligible = search([entry], query: entry.name, settings: settings).total > 0
    if settings.usesWhitelist && !settings.allTypes && !eligible {
        var unrestrictedTypes = settings; unrestrictedTypes.allTypes = true
        if search([entry], query: entry.name, settings: unrestrictedTypes).total > 0 {
            lines.append("类型排除：当前文件类型、额外扩展名及无扩展名规则均未纳入此对象。")
        }
    }
    lines.append(eligible ? "文件查询过滤：通过。" : "文件查询过滤：未通过范围、类型、扩展名、隐藏文件或黑名单规则。")
    if settings.effectiveSearchMode == .lokii {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(search([entry], query: query, settings: settings).total > 0
                ? "关键词：对象本身通过觅见匹配与过滤。" : "关键词：对象本身未通过觅见匹配与过滤。")
        }
        lines.append("Lokii 的索引覆盖、权限、就绪状态和完整匹配总数不可由本地属性检查推断。以下实际请求仍受上游限量约束。")
        lines.append("本次未修改规则或重扫；通过选择器访问对象可能临时改变读取条件。")
        return lines.joined(separator: "\n\n")
    }
    let indexedEntry = entries.first { $0.path == path || $0.path == suppliedPath }
    let indexed = indexedEntry != nil
    lines.append(indexed ? "索引：包含此对象。" : "索引：暂不包含此对象；也可能受扫描遍历限制或尚未完成校准影响。")
    let related = errors.filter { error in error.contains(path) || roots.contains(where: { root in error.contains(root) }) }
    if !related.isEmpty { lines.append("当前扫描错误（相关范围，最多5条）：\n" + related.prefix(5).joined(separator: "\n")) }
    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if search([entry], query: query, settings: settings).total == 0 {
            lines.append("关键词：未通过当前匹配和过滤条件。")
        } else if indexed {
            let files = search(entries, query: query, settings: settings)
            let merged = mergeSettings(files, pages: SettingsDestination.available(), query: query, settings: settings)
            lines.append(merged.items.contains { $0.file?.path == indexedEntry?.path } ? "结果：位于当前候选数量上限内。" : "结果：匹配，但被排序及候选数量上限截断。")
        } else { lines.append("关键词：对象本身可以匹配，但尚不在当前索引中。") }
    }
    lines.append("本次未修改规则或重扫。通过选择器访问对象可能临时改变读取条件；此报告不等同于全盘授权检测。")
    return lines.joined(separator: "\n\n")
}
