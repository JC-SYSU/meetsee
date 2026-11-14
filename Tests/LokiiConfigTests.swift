import Foundation
@main struct LokiiConfigTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("meetsee-config-test-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("config.toml"), backups = root.appendingPathComponent("backups")
        let original = "# 注释与其他字段保持原样\n[index]\nindex_paths = [\"~\"]\n\n[shortcut]\ntoggle_window = \"Cmd+Shift+Space\"\n"
        try Data(original.utf8).write(to: file)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        var doc = try LokiiConfigDocument(url: file)
        precondition(tryNoOp(&doc, text: original, backups: backups))
        let changed = original.replacingOccurrences(of: "[\"~\"]", with: "[\"~\", \"/Applications\"]")
        let backup = try doc.save(changed, backups: backups)!
        let saved = try String(contentsOf: file, encoding: .utf8)
        let backupText = try String(contentsOf: backup, encoding: .utf8)
        precondition(saved == changed && backupText == original)
        let permissions = try fm.attributesOfItem(atPath: backup.path)[.posixPermissions] as? NSNumber
        precondition(permissions?.intValue == 0o600)
        try Data((changed + "# 外部修改\n").utf8).write(to: file)
        do { _ = try doc.save(original, backups: backups); preconditionFailure("conflict overwritten") }
        catch { precondition(error.localizedDescription.contains("其他程序")) }
        let link = root.appendingPathComponent("linked.toml")
        try fm.createSymbolicLink(at: link, withDestinationURL: file)
        var linked = try LokiiConfigDocument(url: link)
        _ = try linked.save(original, backups: backups)
        let destination = try fm.destinationOfSymbolicLink(atPath: link.path)
        precondition(destination == file.path)
        let targetText = try String(contentsOf: file, encoding: .utf8)
        precondition(targetText == original)
        let missing = root.appendingPathComponent("missing.toml")
        do { _ = try LokiiConfigDocument(url: missing); preconditionFailure("missing auto-created") } catch {}
        if CommandLine.arguments.count > 1 {
            var settings = Settings(); settings.roots = [root.path]; settings.exclusions = [root.appendingPathComponent("缓存").path]
            settings.blacklistEnabled = true; settings.showHidden = true
            let change = try LokiiScopeSync.synchronize(settings, url: file, backups: backups, tool: URL(fileURLWithPath: CommandLine.arguments[1]))
            precondition(change.backup != nil)
            let synced = try String(contentsOf: file, encoding: .utf8)
            precondition(synced.contains("max_results = 5000") && synced.contains("include_hidden = true") && synced.contains("exclude = []") && synced.contains("Cmd+Shift+Space"))
            let noChange = try LokiiScopeSync.synchronize(settings, url: file, backups: backups, tool: URL(fileURLWithPath: CommandLine.arguments[1]))
            precondition(noChange.backup == nil)
            try change.rollback(backups: backups)
            let rolledBack = try String(contentsOf: file, encoding: .utf8)
            precondition(rolledBack == original)
            print("PASS: automatic scope sync through bundled parser, unrelated config preserved, no-op sync and conditional rollback")
        }
        print("PASS: full-document config save/no-op, original backup, private permissions, external edit conflict, symlink preservation, no automatic config creation")
        print("Config test artifacts: " + root.path)
    }
    static func tryNoOp(_ doc: inout LokiiConfigDocument, text: String, backups: URL) -> Bool {
        do { return try doc.save(text, backups: backups) == nil } catch { return false }
    }
}
