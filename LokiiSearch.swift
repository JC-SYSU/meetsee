import Foundation
import Darwin

struct LokiiRecord: Codable {
    let path: String
    let isDir: Bool
    let modified: Double
}
struct LokiiResponse: Decodable {
    let results: [LokiiRecord]
    let error: String?
}
struct LokiiError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// One JSON line per connection. No subprocesses, shell, config writes or app launch.
struct LokiiClient {
    var path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/lokii/query.sock").path
    var timeout: TimeInterval = 0.8
    // Prefetch before local filtering; this is not the displayed candidate count.
    static let prefetchLimit = 5000
    static let responseLimit = 4 * 1024 * 1024
    func query(_ query: String, mode: String = "substring", limit: Int = LokiiClient.prefetchLimit,
               cancelled: () -> Bool = { false }) throws -> LokiiResponse {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LokiiError(message: "无法创建 Lokii 连接") }
        defer { Darwin.close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw LokiiError(message: "无法配置 Lokii 连接") }
        func ready(_ events: Int16) throws {
            while true {
                if cancelled() { throw LokiiError(message: "查询已取消") }
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else { throw LokiiError(message: "Lokii 请求超时") }
                var item = pollfd(fd: fd, events: events, revents: 0)
                let result = poll(&item, 1, Int32(min(25, max(1, remaining * 1000))))
                if result > 0 { return } // recv / SO_ERROR reports EOF and connection errors.
                if result < 0 && errno != EINTR { throw LokiiError(message: "Lokii 连接中断") }
            }
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw LokiiError(message: "Lokii socket 路径过长") }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if connected != 0 {
            guard errno == EINPROGRESS || errno == EAGAIN else { throw LokiiError(message: "无法连接 Lokii，请确认应用已启动") }
            try ready(Int16(POLLOUT))
            var code: Int32 = 0; var size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &code, &size) == 0, code == 0 else { throw LokiiError(message: "无法连接 Lokii，请确认应用已启动") }
        }
        struct Request: Encodable { let q: String; let mode: String; let limit: Int }
        var request = try JSONEncoder().encode(Request(q: query, mode: mode, limit: limit))
        request.append(10)
        guard request.count < 64 * 1024 else { throw LokiiError(message: "检索词过长") }
        var offset = 0
        while offset < request.count {
            try ready(Int16(POLLOUT))
            let sent = request.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!.advanced(by: offset), request.count - offset, 0) }
            if sent > 0 { offset += sent }
            else if sent == 0 || (errno != EAGAIN && errno != EINTR) { throw LokiiError(message: "Lokii 发送失败") }
        }
        var response = Data(); var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            try ready(Int16(POLLIN))
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            if count > 0 {
                let chunk = buffer.prefix(count)
                let newline = chunk.firstIndex(of: 10)
                response.append(contentsOf: chunk.prefix(newline ?? count))
                guard response.count <= Self.responseLimit else { throw LokiiError(message: "Lokii 响应过大") }
                if newline != nil {
                    let decoded: LokiiResponse
                    do { decoded = try JSONDecoder().decode(LokiiResponse.self, from: response) }
                    catch { throw LokiiError(message: "Lokii 响应格式不兼容") }
                    if let error = decoded.error, !error.isEmpty { throw LokiiError(message: "Lokii：" + error) }
                    return decoded
                }
            } else if count == 0 { throw LokiiError(message: "Lokii 在返回完整响应前断开连接") }
            else if errno != EAGAIN && errno != EINTR { throw LokiiError(message: "Lokii 读取失败") }
        }
    }
}

/// One parent-owned package helper; all requests use private pipes, never query.sock.
struct LokiiManagedConfig: Codable, Equatable {
    let roots: [String]
    let excludedPaths: [String]
    let includeHidden: Bool
    let maxResults: Int
    let cacheDirectory: String
    let listen: Bool
    let networkRescanMinutes: Int
    init(settings: Settings, cache: URL) {
        let scope = IndexScope(settings)
        roots = scope.roots; excludedPaths = scope.excluded
        includeHidden = settings.showHidden; maxResults = LokiiClient.prefetchLimit
        cacheDirectory = cache.path; listen = settings.autoRefresh; networkRescanMinutes = 5
    }
}

final class LokiiProcess {
    static let responseLimit = 16 * 1024 * 1024
    private let condition = NSCondition(), writer = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var sequence = 0
    private var session = UUID()
    private var expectedStop = false
    private var waiting = Set<Int>()
    private var responses: [Int: [String: Any]] = [:]
    private var status: [String: Any] = [:]
    var onStatus: (([String: Any]) -> Void)?
    var onUnexpectedExit: (() -> Void)?
    var executable: URL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/meetsee-lokii-engine")
    private var savedConfiguration: LokiiManagedConfig?
    var configuration: LokiiManagedConfig? { condition.lock(); defer { condition.unlock() }; return savedConfiguration }
    var snapshot: [String: Any] { condition.lock(); defer { condition.unlock() }; return status }
    var pid: Int32? { condition.lock(); defer { condition.unlock() }; return process?.isRunning == true ? process?.processIdentifier : nil }

    func start(settings: Settings, cache: URL) throws {
        let next = LokiiManagedConfig(settings: settings, cache: cache)
        if configuration == next, pid != nil { return }
        stop()
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw LokiiError(message: "包内 Lokii 引擎缺失，请重新构建觅见") }
        let child = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.executableURL = executable; child.arguments = ["--stdio"]
        var environment = ProcessInfo.processInfo.environment
        for key in ["NO_COLOR", "FORCE_COLOR", "CLICOLOR", "CLICOLOR_FORCE", "TERM", "COLORTERM"] { environment.removeValue(forKey: key) }
        child.environment = environment
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = stderr
        let token = UUID()
        condition.lock(); session = token; expectedStop = false; process = child; input = stdin.fileHandleForWriting; status = [:]; condition.unlock()
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        child.terminationHandler = { [weak self] child in
            guard let self else { return }
            self.condition.lock()
            let unexpected = self.session == token && !self.expectedStop
            if unexpected {
                self.status = ["phase": "failed", "queryable": false, "error": "内置引擎退出（\(child.terminationStatus)）"]
                self.condition.broadcast()
            }
            let value = self.status; self.condition.unlock()
            if unexpected { self.onStatus?(value); self.onUnexpectedExit?() }
        }
        do { try child.run() }
        catch { stop(); throw error }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var buffer = Data()
            defer { try? stdout.fileHandleForReading.close() }
            do {
                while true {
                    let chunk = stdout.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    guard buffer.count <= Self.responseLimit else { throw LokiiError(message: "内置引擎响应过大") }
                    while let newline = buffer.firstIndex(of: 10) {
                        let data = buffer[..<newline]; buffer.removeSubrange(...newline)
                        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              object["protocol"] as? Int == 1 else { throw LokiiError(message: "内置引擎协议不兼容") }
                        self?.receive(object, session: token)
                    }
                }
            } catch { self?.failedRead(error, session: token) }
        }
        DispatchQueue.global(qos: .utility).async {
            // Drain diagnostics continuously: a full stderr pipe must never stall the engine.
            while !stderr.fileHandleForReading.availableData.isEmpty { }
            try? stderr.fileHandleForReading.close()
        }
        do {
            let hello = try request("hello")
            guard (hello["capabilities"] as? [String: Any])?["statusEvents"] as? Bool == true else {
                throw LokiiError(message: "包内引擎版本不兼容")
            }
            let data = try JSONEncoder().encode(next)
            _ = try request("initialize", fields: ["config": try JSONSerialization.jsonObject(with: data)])
            condition.lock(); savedConfiguration = next; condition.unlock()
        } catch { stop(); throw error }
    }
    private func receive(_ object: [String: Any], session token: UUID) {
        condition.lock()
        guard session == token else { condition.unlock(); return }
        if object["event"] as? String == "status", let value = object["data"] as? [String: Any] {
            status = value; condition.unlock(); onStatus?(value); return
        }
        if let id = object["id"] as? Int, waiting.contains(id) { responses[id] = object; condition.broadcast() }
        condition.unlock()
    }
    private func failedRead(_ error: Error, session token: UUID) {
        condition.lock()
        guard session == token else { condition.unlock(); return }
        status = ["phase": "failed", "queryable": false, "error": error.localizedDescription]
        let value = status; condition.broadcast(); let child = process; condition.unlock()
        onStatus?(value); if child?.isRunning == true { child?.terminate() }
    }
    func request(_ op: String, fields: [String: Any] = [:], timeout: TimeInterval = 2,
                 cancelled: () -> Bool = { false }) throws -> [String: Any] {
        if cancelled() { throw LokiiError(message: "查询已取消") }
        condition.lock()
        guard let child = process, child.isRunning, let input else { condition.unlock(); throw LokiiError(message: "内置引擎未运行") }
        guard waiting.count < 8 else { condition.unlock(); throw LokiiError(message: "内置引擎请求繁忙") }
        sequence += 1; let id = sequence, token = session; waiting.insert(id); condition.unlock()
        defer { condition.lock(); waiting.remove(id); responses.removeValue(forKey: id); condition.unlock() }
        var payload = fields; payload["protocol"] = 1; payload["id"] = id; payload["op"] = op
        var data = try JSONSerialization.data(withJSONObject: payload); data.append(10)
        guard data.count <= 65536 else { throw LokiiError(message: "内置引擎请求过大") }
        writer.lock()
        do { try input.write(contentsOf: data); writer.unlock() }
        catch { writer.unlock(); throw LokiiError(message: "内置引擎连接已关闭") }
        let end = Date().addingTimeInterval(timeout)
        condition.lock(); defer { condition.unlock() }
        while responses[id] == nil {
            if cancelled() { throw LokiiError(message: "查询已取消") }
            guard session == token, child.isRunning else { throw LokiiError(message: "内置引擎连接已关闭") }
            guard Date() < end else { throw LokiiError(message: "内置引擎请求超时") }
            _ = condition.wait(until: min(end, Date().addingTimeInterval(0.025)))
        }
        let response = responses[id]!
        guard response["ok"] as? Bool == true else { throw LokiiError(message: response["error"] as? String ?? "内置引擎请求失败") }
        return response["data"] as? [String: Any] ?? [:]
    }
    func query(_ query: String, mode: String, limit: Int, cancelled: () -> Bool) throws -> LokiiResponse {
        let data = try request("search", fields: ["query": query, "mode": mode, "limit": limit], cancelled: cancelled)
        return try JSONDecoder().decode(LokiiResponse.self, from: JSONSerialization.data(withJSONObject: data))
    }
    func rebuild() throws { _ = try request("rebuild") }
    func stop() {
        // Called on the lifecycle queue, not the UI/search queue.
        condition.lock(); expectedStop = true; condition.unlock()
        if pid != nil { _ = try? request("shutdown", timeout: 4) }
        condition.lock(); session = UUID(); let child = process; let handle = input
        process = nil; input = nil; savedConfiguration = nil; responses.removeAll(); waiting.removeAll(); condition.broadcast(); condition.unlock()
        try? handle?.close()
        guard let child else { return }
        let end = Date().addingTimeInterval(0.5)
        while child.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.01) }
        if child.isRunning { child.terminate() }
        let forced = Date().addingTimeInterval(1)
        while child.isRunning && Date() < forced { Thread.sleep(forTimeInterval: 0.01) }
        if child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
        child.waitUntilExit()
    }
}

struct LokiiSearchResult {
    let files: SearchResult
    let source: [Entry]
    let note: String
}

/// Used only on the serial search queue. The application alias catalog is obtained
/// from Lokii itself, never by querying or scanning the native index.
final class LokiiEngine {
    var client: LokiiClient? // Only injected by legacy socket fixtures, never a production fallback.
    let managed: LokiiProcess?
    init(process: LokiiProcess? = nil) { managed = process }
    private var apps: [Entry] = []
    private var appsUpdated = Date.distantPast
    func reset() { apps = []; appsUpdated = .distantPast }
    func searchFiles(query: String, settings: Settings, cancelled: () -> Bool = { false }) throws -> LokiiSearchResult {
        let terms = query.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = terms.first else { return LokiiSearchResult(files: SearchResult(entries: [], total: 0), source: [], note: "") }
        let deadline = ProcessInfo.processInfo.systemUptime + (client?.timeout ?? 2)
        func request(_ q: String, mode: String = "substring") throws -> [LokiiRecord] {
            if let managed { return try managed.query(q, mode: mode, limit: LokiiClient.prefetchLimit, cancelled: cancelled).results }
            guard var bounded = client else { throw LokiiError(message: "内置引擎尚未连接") }
            bounded.timeout = max(0, deadline - ProcessInfo.processInfo.systemUptime)
            return try bounded.query(q, mode: mode, cancelled: cancelled).results
        }
        // Query one term upstream, then apply all existing terms and rules locally.
        // Lokii's inline syntax is not advertised as a separate Meet&See feature.
        var records = try request(first)
        if settings.matchPath && !first.contains("/") && !first.contains(":") {
            records += try request(first + "/")
        }
        var warnings: [String] = []
        if Date().timeIntervalSince(appsUpdated) > 60 {
            do {
                let catalog = try request("\\.app$", mode: "regex")
                let adapted = adapt(catalog, settings: settings, cancelled: cancelled).filter { $0.kind == .application }
                if cancelled() { throw LokiiError(message: "查询已取消") }
                apps = adapted; appsUpdated = Date()
            } catch {
                if cancelled() { throw error }
                // A valid primary response remains useful if alias lookup fails.
                warnings.append("应用别名暂未更新")
            }
        }
        let source = unique(adapt(records, settings: settings, cancelled: cancelled) + apps)
        if cancelled() { throw LokiiError(message: "查询已取消") }
        let files = search(source, query: query, settings: settings, cancelled: cancelled)
        if records.count >= LokiiClient.prefetchLimit { warnings.insert("达到预取上限 · 结果可能不完整", at: 0) }
        return LokiiSearchResult(files: files, source: source, note: warnings.joined(separator: " · "))
    }
    private func unique(_ entries: [Entry]) -> [Entry] {
        var paths = Set<String>()
        return entries.filter { paths.insert($0.path).inserted }
    }
    func adapt(_ records: [LokiiRecord], settings: Settings, cancelled: () -> Bool = { false }) -> [Entry] {
        let roots = settings.searchRoots.map(expandedPath)
        let excluded = BlacklistFilter(settings).directories
        return records.compactMap { record in
            guard !cancelled(), record.path.hasPrefix("/"), !record.path.utf8.contains(0) else { return nil }
            // Keep POSIX identity: URL.standardizedFileURL may rewrite /tmp
            // into /tmp, whereas native scope paths use realpath.
            let path = record.path
            guard !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return nil }
            let url = URL(fileURLWithPath: path)
            guard let root = roots.filter({ within(path, $0) }).min(by: { $0.count < $1.count }),
                  !excluded.contains(where: { within(path, $0) }) else { return nil }
            // Match native traversal: no hidden ancestors, package internals or
            // descendants of symlink directories. An explicit root remains allowed.
            var ancestor = path
            while ancestor != root && within(ancestor, root) {
                let ancestorURL = URL(fileURLWithPath: ancestor)
                guard let v = try? ancestorURL.resourceValues(forKeys: [.isHiddenKey, .isPackageKey, .isSymbolicLinkKey]) else { return nil }
                if !settings.showHidden && (v.isHidden == true || (ancestor as NSString).lastPathComponent.hasPrefix(".")),
                   !isSystemApplicationLink(ancestorURL, symbolic: v.isSymbolicLink == true) { return nil }
                if ancestor != path && (v.isPackage == true || v.isSymbolicLink == true) { return nil }
                ancestor = (ancestor as NSString).deletingLastPathComponent
            }
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isAliasFileKey, .isSymbolicLinkKey, .contentModificationDateKey]) else { return nil }
            return Entry(path: path, directory: values.isDirectory == true,
                modified: values.contentModificationDate?.timeIntervalSince1970 ?? record.modified,
                isFinderAlias: values.isAliasFile == true, isSymbolicLink: values.isSymbolicLink == true)
        }
    }
}
