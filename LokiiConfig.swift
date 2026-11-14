import Foundation

/// Full-document editing: never parses/reformats TOML or replaces fields by regex.
/// Backups are private and outside Lokii's watched configuration directory.
struct LokiiConfigDocument {
    let url: URL
    private let target: URL
    private(set) var original: Data
    var text: String { String(decoding: original, as: UTF8.self) }
    init(url: URL) throws {
        self.url = url
        target = url.resolvingSymlinksInPath()
        original = try Data(contentsOf: target)
        guard String(data: original, encoding: .utf8) != nil else { throw LokiiError(message: "配置不是有效的 UTF-8 文本") }
    }
    mutating func save(_ text: String, backups: URL) throws -> URL? {
        let fm = FileManager.default
        guard url.resolvingSymlinksInPath() == target, try Data(contentsOf: target) == original else {
            throw LokiiError(message: "配置已被其他程序修改，请重新载入后再编辑；本次没有覆盖。")
        }
        let replacement = Data(text.utf8)
        guard replacement != original else { return nil }
        let attributes = try fm.attributesOfItem(atPath: target.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw LokiiError(message: "配置目标不是普通文件") }
        try fm.createDirectory(at: backups, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let backup = backups.appendingPathComponent("config-\(UUID().uuidString).toml")
        try original.write(to: backup, options: .withoutOverwriting)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        // Recheck after backup creation, which may take time on external storage.
        guard url.resolvingSymlinksInPath() == target, try Data(contentsOf: target) == original else {
            throw LokiiError(message: "配置在保存前发生变化，已停止写入；请重新载入。")
        }
        try replacement.write(to: target, options: .atomic)
        if let permissions = attributes[.posixPermissions] { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path) }
        original = replacement
        return backup
    }
}

struct LokiiConfigChange {
    var document: LokiiConfigDocument
    let before: Data
    let backup: URL?
    func rollback(backups: URL) throws {
        guard backup != nil else { return }
        var current = document
        _ = try current.save(String(decoding: before, as: UTF8.self), backups: backups)
    }
}

struct LokiiScopeSync {
    static func scopeText(_ settings: Settings) throws -> String {
        func array(_ paths: [String]) throws -> String {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
            return String(decoding: try encoder.encode(paths), as: UTF8.self)
        }
        let scope = IndexScope(settings)
        // Lokii defaults are not Meet&See rules: leaving exclude/node_modules or
        // exclude_paths/System would silently omit otherwise eligible files.
        return "index_paths = \(try array(scope.roots))\nexclude = []\nexclude_paths = \(try array(scope.excluded))\ninclude_hidden = \(settings.showHidden ? "true" : "false")\nmax_results = \(LokiiClient.prefetchLimit)\n"
    }
    static func synchronize(_ settings: Settings, url: URL, backups: URL, tool: URL) throws -> LokiiConfigChange {
        var document = try LokiiConfigDocument(url: url)
        let original = document.original
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("meetsee-lokii-scope-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let snapshot = temp.appendingPathComponent("snapshot.toml")
        defer { try? FileManager.default.removeItem(at: snapshot); try? FileManager.default.removeItem(at: temp) }
        try original.write(to: snapshot)
        let process = Process(); process.executableURL = tool; process.arguments = [snapshot.path]
        let input = Pipe(), output = Pipe(), error = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = error
        try process.run()
        input.fileHandleForWriting.write(Data(try scopeText(settings).utf8))
        try input.fileHandleForWriting.close()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        let detail = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let patched = String(data: result, encoding: .utf8) else {
            throw LokiiError(message: "Lokii 配置未同步，原文件未覆盖：" + String(decoding: detail, as: UTF8.self))
        }
        let backup = try document.save(patched, backups: backups)
        return LokiiConfigChange(document: document, before: original, backup: backup)
    }
}
