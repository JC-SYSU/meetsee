import Foundation
func referenceSearch(_ entries: [Entry], query: String, settings: Settings) -> SearchResult {
    let q = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !q.isEmpty else { return SearchResult(entries: [], total: 0) }
    let terms = q.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    let extensions = extensionSet(settings.customExtensions)
    let blacklist = BlacklistFilter(settings)
    let roots = settings.searchRoots.map(expandedPath)
    var hits: [(Entry, Int)] = []
    for e in entries {
        let candidate = (settings.matchPath ? [e.searchPath] : []) + e.searchAliases
        guard terms.allSatisfy({ term in candidate.contains { $0.contains(term) } }) else { continue }
        guard let root = roots.first(where: { within(e.path, $0) }), !blacklist.rejects(e) else { continue }
        if !settings.showHidden && e.path.dropFirst(root.count).split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
        let extensionless = settings.includeExtensionless == true && e.kind != .folder && e.kind != .application && URL(fileURLWithPath: e.path).pathExtension.isEmpty
        guard !settings.usesWhitelist || settings.allTypes || settings.includesKind(e) || extensionless || (!extensions.isEmpty && extensions.contains(URL(fileURLWithPath: e.path).pathExtension.lowercased())) else { continue }
        let score = e.searchAliases.contains(q) ? 0 : (e.searchAliases.contains { $0.hasPrefix(q) } ? 1 : (terms.allSatisfy { term in e.searchAliases.contains { $0.contains(term) } } ? 2 : 3))
        hits.append((e, score))
    }
    hits.sort {
        if settings.applicationsFirst == true, ($0.0.kind == .application) != ($1.0.kind == .application) {
            return $0.0.kind == .application
        }
        if $0.1 != $1.1 { return $0.1 < $1.1 }
        if settings.sortModified && $0.0.modified != $1.0.modified { return $0.0.modified > $1.0.modified }
        if $0.0.name != $1.0.name { return $0.0.name.localizedStandardCompare($1.0.name) == .orderedAscending }
        return $0.0.path < $1.0.path
    }
    return SearchResult(entries: Array(hits.prefix(max(1, settings.limit))).map { $0.0 }, total: hits.count)
}

