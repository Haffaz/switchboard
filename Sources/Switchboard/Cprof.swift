import Foundation
import SwitchboardCore

struct CprofError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Runs the bundled `cprof` script, which owns account folders and settings.
/// Always off the main thread, so the menu never waits on it.
enum Cprof {
    static var scriptURL: URL {
        (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("cprof/bin/cprof")
    }

    @discardableResult
    static func run(_ args: [String]) async throws -> String {
        let script = scriptURL.path
        let environment = environment(claudeApp: ClaudeDesktop.appURL?.path)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try runBlocking(script, args, environment) })
            }
        }
    }

    static func profiles() async throws -> [Profile] {
        try Profile.decodeList(try await run(["list", "--json"]))
    }

    /// Apps opened from Finder get a short PATH. Add the usual tool folders,
    /// and tell the script where Claude Desktop is installed.
    private static func environment(claudeApp: String?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extra = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        env["CPROF_DESKTOP_APP"] = claudeApp
        for key in ["CLAUDE_CONFIG_DIR", "CPROF_PROFILE", "CPROF_PS_FILE"] { env.removeValue(forKey: key) }
        return env
    }

    private static func runBlocking(_ script: String, _ args: [String], _ env: [String: String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script] + args
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()

        // Drain both pipes at once; reading one to the end first can deadlock
        // when the other fills up.
        let errBox = DataBox()
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            errBox.set(err.fileHandleForReading.readDataToEndOfFile())
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let text = String(decoding: errBox.get(), as: UTF8.self)
                .replacingOccurrences(of: "cprof: ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CprofError(message: text.isEmpty ? "Something went wrong." : text.prefix(1).uppercased() + text.dropFirst())
        }
        return String(decoding: outData, as: UTF8.self)
    }
}

/// A lock-protected Data holder for handing a result between two threads.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ value: Data) { lock.lock(); data = value; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}
