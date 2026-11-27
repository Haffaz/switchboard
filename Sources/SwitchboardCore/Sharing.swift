import Foundation

/// The optional things accounts can share, beyond the always-shared rules,
/// skills, plugins and settings. Each is off until switched on.
public enum SharedThing: String, CaseIterable, Codable, Sendable {
    /// Claude Code sessions: one folder, linked into every account.
    case history
    /// Claude Code MCP servers: copied from the default account.
    case connectors
    /// Claude Desktop extensions and local MCP servers: copied from the default account.
    case extensions

    public var title: String {
        switch self {
        case .history: return "Claude Code History"
        case .connectors: return "Claude Code Connectors"
        case .extensions: return "Desktop Extensions"
        }
    }

    public var summary: String {
        switch self {
        case .history: return "Resume any account's Claude Code sessions from any other account."
        case .connectors: return "MCP servers added in Default are copied to the other accounts."
        case .extensions: return "Extensions installed in Default's Claude Desktop are copied to the other accounts."
        }
    }
}

/// Sharing between accounts. The default account is always the source: its
/// folders are read, and for history other accounts link to them. Nothing
/// here reads or copies a sign-in.
public struct Sharing: Sendable {
    public let store: AccountStore
    public init(store: AccountStore = AccountStore()) { self.store = store }

    private var fm: FileManager { .default }
    private var paths: Paths { store.paths }
    private var settingsFile: URL { paths.profilesHome.appendingPathComponent(".sharing.json") }

    /// Folders that make up Claude Code's history. Only folders: a linked
    /// single file can be silently replaced by a program that saves by
    /// writing a new file and renaming it.
    static let historyFolders = ["projects", "file-history", "todos"]
    /// What makes up Claude Desktop's installed extensions.
    static let extensionItems = ["Claude Extensions", "Claude Extensions Settings", "extensions-installations.json"]
    static let extensionRegistry = "extensions-installations.json"
    static let desktopConfig = "claude_desktop_config.json"
    static let serversKey = "mcpServers"

    private var otherAccounts: [String] { store.names().filter { $0 != Profile.defaultName } }

    // MARK: - Settings

    public func enabled() -> Set<SharedThing> {
        guard let data = try? Data(contentsOf: settingsFile),
              let things = try? JSONDecoder().decode([SharedThing].self, from: data) else { return [] }
        return Set(things)
    }

    public func isOn(_ thing: SharedThing) -> Bool { enabled().contains(thing) }

    /// Switch a kind of sharing on or off, and bring every account in line.
    /// Returns notes worth showing, such as files kept aside.
    @discardableResult
    public func set(_ thing: SharedThing, on: Bool) throws -> [String] {
        var things = enabled()
        if on { things.insert(thing) } else { things.remove(thing) }
        try fm.createDirectory(at: paths.profilesHome, withIntermediateDirectories: true)
        let ordered = SharedThing.allCases.filter(things.contains)
        try JSONEncoder().encode(ordered).write(to: settingsFile, options: .atomic)
        if !on, thing == .history { otherAccounts.forEach(unlinkHistory) }
        return try apply()
    }

    /// Make every account match the current settings. Safe to run any time.
    /// Desktop extensions are left to `prepareDesktop`, which runs when an
    /// account's Claude Desktop is about to start.
    @discardableResult
    public func apply() throws -> [String] {
        let things = enabled()
        var notes: [String] = []
        for name in otherAccounts {
            if things.contains(.history) { notes += try linkHistory(name) }
            if things.contains(.connectors) { try syncConnectors(name) }
        }
        return notes
    }

    // MARK: - Claude Code history

    /// Point an account's history folders at the default account's. Sessions
    /// the account already had are moved in first, so nothing is lost.
    func linkHistory(_ name: String) throws -> [String] {
        var notes: [String] = []
        for folder in Self.historyFolders {
            let shared = paths.defaultCLIDir.appendingPathComponent(folder)
            let own = store.cliDir(name).appendingPathComponent(folder)
            guard isDirectory(shared) else { continue }
            if let target = try? fm.destinationOfSymbolicLink(atPath: own.path) {
                if target == shared.path { continue }  // already linked: leave it alone
                try? fm.removeItem(at: own)
            } else if fm.fileExists(atPath: own.path) {
                if try merge(own, into: shared) {
                    try fm.removeItem(at: own)
                } else {
                    // Something had the same name in both places. Keep the
                    // account's copy aside instead of choosing for the person.
                    let aside = store.cliDir(name).appendingPathComponent("\(folder).before-sharing")
                    try? fm.removeItem(at: aside)
                    try fm.moveItem(at: own, to: aside)
                    notes.append("\(name): some \(folder) could not be merged and were kept in \(aside.lastPathComponent)")
                }
            }
            try fm.createDirectory(at: store.cliDir(name), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: own, withDestinationURL: shared)
        }
        return notes
    }

    /// Stop sharing: remove the links. The shared history stays with the
    /// default account, and this account starts a fresh folder when next used.
    func unlinkHistory(_ name: String) {
        for folder in Self.historyFolders {
            let own = store.cliDir(name).appendingPathComponent(folder)
            if isLink(own) { try? fm.removeItem(at: own) }
        }
    }

    /// Move everything in `source` into `target`, descending into folders
    /// that exist in both. Returns false if something was left behind
    /// because the same file exists in both.
    private func merge(_ source: URL, into target: URL) throws -> Bool {
        var complete = true
        for entry in try fm.contentsOfDirectory(atPath: source.path) {
            let from = source.appendingPathComponent(entry), to = target.appendingPathComponent(entry)
            if !fm.fileExists(atPath: to.path) {
                try fm.moveItem(at: from, to: to)
            } else if isDirectory(from), isDirectory(to), !isLink(from) {
                if try !merge(from, into: to) { complete = false } else { try fm.removeItem(at: from) }
            } else {
                complete = false
            }
        }
        return complete
    }

    // MARK: - Claude Code connectors

    /// Copy the default account's MCP servers into an account's settings
    /// file. Servers the account added itself are kept; on a name clash the
    /// default account's version wins. Returns true if the file changed.
    @discardableResult
    func syncConnectors(_ name: String) throws -> Bool {
        try mergeServers(from: paths.defaultCLIJSON, into: store.cliDir(name).appendingPathComponent(".claude.json"))
    }

    /// Merge the "mcpServers" entry of one JSON file into another, leaving
    /// every other entry of the target as it was.
    private func mergeServers(from source: URL, into target: URL) throws -> Bool {
        guard let wanted = Self.object(source)?[Self.serversKey] as? [String: Any], !wanted.isEmpty else { return false }
        var document = Self.object(target) ?? [:]
        let current = document[Self.serversKey] as? [String: Any] ?? [:]
        let merged = current.merging(wanted) { _, fromDefault in fromDefault }
        guard !NSDictionary(dictionary: merged).isEqual(to: current) else { return false }
        document[Self.serversKey] = merged
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .withoutEscapingSlashes])
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)  // it sits beside a sign-in
        return true
    }

    private static func object(_ file: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Claude Desktop extensions

    /// Bring an account's Claude Desktop extensions in line with the default
    /// account's, if that sharing is on. Call this just before the account's
    /// Claude Desktop starts, never while it is running. Returns true if
    /// anything was copied.
    @discardableResult
    public func prepareDesktop(_ name: String) throws -> Bool {
        guard isOn(.extensions), name != Profile.defaultName, let target = store.desktopDir(name) else { return false }
        let source = paths.defaultDesktopDir
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        var changed = try mergeServers(from: source.appendingPathComponent(Self.desktopConfig),
                                       into: target.appendingPathComponent(Self.desktopConfig))

        let registry = source.appendingPathComponent(Self.extensionRegistry)
        guard fm.fileExists(atPath: registry.path) else { return changed }
        let upToDate = fm.contentsEqual(atPath: registry.path, andPath: target.appendingPathComponent(Self.extensionRegistry).path)
            && Self.extensionItems.allSatisfy { item in
                !fm.fileExists(atPath: source.appendingPathComponent(item).path)
                    || fm.fileExists(atPath: target.appendingPathComponent(item).path)
            }
        guard !upToDate else { return changed }
        for item in Self.extensionItems {
            let from = source.appendingPathComponent(item), to = target.appendingPathComponent(item)
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.removeItem(at: to)
            try fm.copyItem(at: from, to: to)  // on APFS this shares storage until either copy changes
            changed = true
        }
        return changed
    }

    // MARK: - Helpers

    private func isLink(_ url: URL) -> Bool {
        (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
