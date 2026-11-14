import Foundation

/// This GUI launcher must not relay a developer terminal's color policy to apps.
/// Run before AppKit/NSWorkspace initialization so their environment snapshot is clean.
enum LaunchEnvironment {
    static let terminalVariables = [
        "NO_COLOR", "FORCE_COLOR", "CLICOLOR", "CLICOLOR_FORCE",
        "TERM", "COLORTERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION"
    ]
    static func sanitize() {
        for name in terminalVariables { unsetenv(name) }
    }
}
