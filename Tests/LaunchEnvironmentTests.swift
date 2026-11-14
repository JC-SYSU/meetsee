import AppKit

@main struct LaunchEnvironmentTests {
    static func main() throws {
        for key in LaunchEnvironment.terminalVariables { setenv(key, "1", 1) }
        setenv("QUICKFIND_ENV_TEST_KEEP", "preserved", 1)
        LaunchEnvironment.sanitize()
        for key in LaunchEnvironment.terminalVariables { precondition(getenv(key) == nil) }
        precondition(String(cString: getenv("QUICKFIND_ENV_TEST_KEEP")) == "preserved")
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("meetsee-env-\(UUID())")
        let app = root.appendingPathComponent("Probe.app")
        let contents = app.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleExecutable": "Probe", "CFBundleIdentifier": "cn.meetsee.env-probe", "CFBundlePackageType": "APPL", "LSUIElement": true]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let executable = macOS.appendingPathComponent("Probe")
        let output = root.appendingPathComponent("result")
        // A shell may supply its own TERM; test the inherited color policy directly.
        try "#!/bin/sh\nprintf '%s|%s|%s|%s' \"${NO_COLOR-unset}\" \"${FORCE_COLOR-unset}\" \"${COLORTERM-unset}\" \"$QUICKFIND_ENV_TEST_KEEP\" > '\(output.path)'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        var completed = false
        var launchError: Error?
        NSWorkspace.shared.open(app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            completed = true; launchError = error
        }
        let deadline = Date(timeIntervalSinceNow: 15)
        while Date() < deadline && (!completed || !FileManager.default.fileExists(atPath: output.path)) {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        if let launchError { throw launchError }
        precondition(completed)
        let result = try String(contentsOf: output, encoding: .utf8)
        precondition(result == "unset|unset|unset|preserved", result)
        print("PASS: early environment sanitation and actual NSWorkspace child launch; unrelated variables preserved")
    }
}
