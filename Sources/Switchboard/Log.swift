import Foundation

/// Plain-text log at ~/Library/Logs/Switchboard.log, so a failed sign-in can
/// be traced step by step. Callers must never pass link contents: use
/// LinkRouter.logLabel, which leaves out anything that can carry a code.
enum Log {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Switchboard.log")
    private static let maxBytes = 512 * 1024
    private static let lock = NSLock()

    static func write(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        let line = Data("\(ISO8601DateFormatter().string(from: Date())) \(message)\n".utf8)
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? Int, size > maxBytes {
            try? fm.removeItem(at: fileURL)
        }
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }
}
