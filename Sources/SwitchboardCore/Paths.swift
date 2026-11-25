import Foundation

public struct SwitchboardError: LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Where things live on disk. Real programs use `Paths.live`; tests pass
/// temporary folders.
public struct Paths: Sendable, Equatable {
    public var home: URL
    /// One folder per account: `<profilesHome>/<name>/{cli,desktop}`.
    public var profilesHome: URL
    /// The default account's Claude Code folder (`~/.claude`).
    public var defaultCLIDir: URL
    /// The default account's Claude Code state file (`~/.claude.json`).
    public var defaultCLIJSON: URL
    /// The default account's Claude Desktop data folder.
    public var defaultDesktopDir: URL

    public init(home: URL, profilesHome: URL? = nil) {
        self.home = home
        self.profilesHome = profilesHome ?? home.appendingPathComponent(".claude-profiles")
        defaultCLIDir = home.appendingPathComponent(".claude")
        defaultCLIJSON = home.appendingPathComponent(".claude.json")
        defaultDesktopDir = home.appendingPathComponent("Library/Application Support/Claude")
    }

    /// The real locations. `CPROF_HOME` moves the accounts folder.
    public static var live: Paths {
        let custom = ProcessInfo.processInfo.environment["CPROF_HOME"].flatMap { $0.isEmpty ? nil : $0 }
        return Paths(home: FileManager.default.homeDirectoryForCurrentUser,
                     profilesHome: custom.map { URL(fileURLWithPath: $0) })
    }

    var launchDir: URL { profilesHome.appendingPathComponent(".launch") }
}
