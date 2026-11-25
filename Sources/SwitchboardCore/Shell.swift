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

extension Shell {
    /// Run a program, wait, and return what it printed. Nil if it could not start.
    public static func capture(_ executable: String, _ arguments: [String],
                               environment: [String: String]? = nil) -> (status: Int32, output: Data)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
}

/// What Claude Code itself says about one account's login.
public struct CodeLogin: Equatable, Sendable {
    public let signedIn: Bool
    public let email: String
    public init(signedIn: Bool, email: String) {
        self.signedIn = signedIn
        self.email = email
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

    /// Ask Claude Code whether it is signed in for a config folder (nil means
    /// the default folder). This is the truth: its settings file can keep an
    /// email after the login is gone. Nil if Claude Code could not be asked.
    public static func loginStatus(configDir: URL?) -> CodeLogin? {
        guard let claude = find() else { return nil }
        var environment = ProcessInfo.processInfo.environment
        environment["CLAUDE_CONFIG_DIR"] = configDir?.path
        guard let result = Shell.capture(claude.path, ["auth", "status", "--json"], environment: environment)
        else { return nil }
        return parseLoginStatus(result.output)
    }

    /// Reads `claude auth status --json`. Nil if it is not the expected shape.
    static func parseLoginStatus(_ output: Data) -> CodeLogin? {
        guard let object = (try? JSONSerialization.jsonObject(with: output)) as? [String: Any],
              let signedIn = object["loggedIn"] as? Bool else { return nil }
        return CodeLogin(signedIn: signedIn, email: signedIn ? (object["email"] as? String ?? "") : "")
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
