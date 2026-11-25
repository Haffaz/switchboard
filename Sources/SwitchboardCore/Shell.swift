import Foundation

/// Small helpers for running other programs.
public enum Shell {
    /// Quote a value so a shell reads it back as exactly one word.
    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Run a program and wait. Returns its exit status; output is discarded.
    @discardableResult
    public static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// Finding and driving the Claude Code command-line program.
public enum ClaudeCode {
    /// Where `claude` is installed. Apps opened from Finder get a short
    /// PATH, so the usual install folders are checked too.
    public static func find(environment: [String: String] = ProcessInfo.processInfo.environment,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let fromPath = (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/claude" }
        let usual = [home.path + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                     home.path + "/.claude/local/claude"]
        return (fromPath + usual).first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Sign Claude Code out for one config folder, which also removes its
    /// Keychain entry. Returns false if that could not be done.
    public static func signOut(configDir: URL) -> Bool {
        guard let claude = find() else { return false }
        var environment = ProcessInfo.processInfo.environment
        environment["CLAUDE_CONFIG_DIR"] = configDir.path
        return Shell.run(claude.path, ["auth", "logout"], environment: environment) == 0
    }
}
