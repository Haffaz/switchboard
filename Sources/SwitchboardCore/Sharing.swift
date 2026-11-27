import Foundation

/// The things an account can share with another, beyond the rules, skills,
/// plugins and settings that every account always shares.
public enum SharedThing: String, CaseIterable, Codable, Sendable {
    /// Claude Code sessions. Truly shared: both accounts use one folder.
    case history
    /// Claude Code MCP servers, copied from the other account.
    case connectors
    /// Claude Desktop extensions and local MCP servers, copied from the other account.
    case extensions

    public var title: String {
        switch self {
        case .history: return "Claude Code History"
        case .connectors: return "Claude Code Connectors"
        case .extensions: return "Desktop Extensions"
        }
    }

    /// A one-word name for table headings.
    public var shortTitle: String {
        switch self {
        case .history: return "History"
        case .connectors: return "Connectors"
        case .extensions: return "Extensions"
        }
    }

    /// What choosing a source does, in a sentence.
    public var summary: String {
        switch self {
        case .history: return "Both accounts use one set of Claude Code sessions, in the terminal and in Claude Desktop's Code tab (experimental). Claude Desktop chats are not shared."
        case .connectors: return "The other account's MCP servers are copied in."
        case .extensions: return "The other account's Desktop extensions are copied in when Claude Desktop starts."
        }
    }
}

/// Who shares what with whom. For each account and each kind of thing, an
/// account may name one other account as its source:
///
/// - history: the two accounts end up using one folder. Chains are allowed
///   (A shares with B, B with C: all three share C's folder) but loops are not.
/// - connectors and extensions: copied from the source into the account.
///
/// The default account can be a source but is never a target: Switchboard
/// never writes to the setup you had before. Nothing here reads or copies a
/// sign-in.
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

    // MARK: - Reading the plan

    private struct Plan: Codable {
        var version = 2
        /// account -> thing -> source account
        var sources: [String: [String: String]] = [:]
    }

    /// Every account's sources, for accounts that still exist.
    public func sources() -> [String: [SharedThing: String]] {
        let existing = Set(store.names())
        var result: [String: [SharedThing: String]] = [:]
        for (account, things) in loadPlan().sources where existing.contains(account) {
            var mapped: [SharedThing: String] = [:]
            for (raw, source) in things {
                if let thing = SharedThing(rawValue: raw), existing.contains(source), source != account {
                    mapped[thing] = source
                }
            }
            if !mapped.isEmpty { result[account] = mapped }
        }
        return result
    }

    /// The account `name` shares `thing` with, or nil.
    public func source(_ thing: SharedThing, for name: String) -> String? { sources()[name]?[thing] }

    /// Accounts that take `thing` directly from `name`.
    public func dependents(of name: String, for thing: SharedThing) -> [String] {
        sources().filter { $0.value[thing] == name }.map(\.key).sorted()
    }

    /// The account whose folder holds `name`'s history: follow sources to the end.
    public func historyRoot(of name: String) -> String {
        let all = sources()
        var current = name, seen: Set<String> = [name]
        while let next = all[current]?[.history], !seen.contains(next) {
            seen.insert(next)
            current = next
        }
        return current
    }

    /// Accounts whose history lives in `name`'s folder, other than `name` itself.
    public func historySharers(of name: String) -> [String] {
        sources().keys.filter { $0 != name && historyRoot(of: $0) == name }.sorted()
    }

    private func loadPlan() -> Plan {
        guard let data = try? Data(contentsOf: settingsFile) else { return Plan() }
        if let plan = try? JSONDecoder().decode(Plan.self, from: data) { return plan }
        // The first form of this file was a list of things shared from the
        // default account with every other account.
        if let legacy = try? JSONDecoder().decode([SharedThing].self, from: data) {
            var plan = Plan()
            for name in store.names() where name != Profile.defaultName {
                for thing in legacy { plan.sources[name, default: [:]][thing.rawValue] = Profile.defaultName }
            }
            return plan
        }
        return Plan()
    }

    private func save(_ plan: Plan) throws {
        try fm.createDirectory(at: paths.profilesHome, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(plan).write(to: settingsFile, options: .atomic)
    }

    // MARK: - Changing the plan

    /// Why `target` cannot share `thing` from `source`, or nil if it can.
    public func refusal(_ thing: SharedThing, for target: String, from source: String) -> String? {
        if target == Profile.defaultName { return "The default account is never changed, so it can only be shared from." }
        if source == target { return "An account cannot share with itself." }
        guard store.exists(target), store.exists(source) else { return "That account does not exist." }
        if thing == .history, historyRoot(of: source) == target {
            return "That would share history in a loop."
        }
        return nil
    }

    /// Make `target` share `thing` with `source`, or stop sharing it (nil),
    /// then bring every account in line. Returns notes worth showing, such
    /// as sessions kept aside.
    @discardableResult
    public func setSource(_ thing: SharedThing, for target: String, to source: String?) throws -> [String] {
        try store.require(target)
        if let source, let reason = refusal(thing, for: target, from: source) { throw SwitchboardError(reason) }
        var plan = loadPlan()
        var things = plan.sources[target] ?? [:]
        things[thing.rawValue] = source
        plan.sources[target] = things.isEmpty ? nil : things
        try save(plan)
        if source == nil, thing == .history { unlinkHistory(target) }
        return try apply()
    }

    // MARK: - Same as Default

    /// True when the account shares all three things with the default account.
    public func isSameAsDefault(_ name: String) -> Bool {
        guard name != Profile.defaultName, let things = sources()[name] else { return false }
        return SharedThing.allCases.allSatisfy { things[$0] == Profile.defaultName }
    }

    /// Make an account share history, connectors and extensions with the
    /// default account, or share none of them. The usual set-up when extra
    /// accounts are there to keep working when another reaches its limit.
    @discardableResult
    public func setSameAsDefault(_ name: String, _ on: Bool) throws -> [String] {
        try store.require(name)
        guard name != Profile.defaultName else {
            throw SwitchboardError("The default account is never changed, so it can only be shared from.")
        }
        var plan = loadPlan()
        if on {
            var things = plan.sources[name] ?? [:]
            for thing in SharedThing.allCases { things[thing.rawValue] = Profile.defaultName }
            plan.sources[name] = things
        } else {
            plan.sources[name] = nil
        }
        try save(plan)
        if !on { unlinkHistory(name) }
        return try apply()
    }

    /// Forget an account that is being removed: its own sources, and every
    /// copy taken from it. History cannot be forgotten this way; callers must
    /// first check `historySharers(of:)`, because those accounts' sessions
    /// live in the folder being removed.
    public func forget(_ name: String) throws {
        var plan = loadPlan()
        plan.sources[name] = nil
        for account in plan.sources.keys {
            plan.sources[account] = plan.sources[account]?.filter { $0.value != name }
            if plan.sources[account]?.isEmpty == true { plan.sources[account] = nil }
        }
        try save(plan)
    }

    /// Make every account match the plan. Safe to run any time; does nothing
    /// when everything is already in place. Desktop extensions are left to
    /// `prepareDesktop`, which runs just before an account's Claude starts.
    @discardableResult
    public func apply() throws -> [String] {
        var notes: [String] = []
        for (name, things) in sources().sorted(by: { $0.key < $1.key }) {
            if things[.history] != nil { notes += try linkHistory(name, to: historyRoot(of: name)) }
            if let source = things[.connectors] { try syncConnectors(name, from: source) }
        }
        return notes
    }

    // MARK: - Where each account keeps things

    private func cliJSON(_ name: String) -> URL {
        name == Profile.defaultName ? paths.defaultCLIJSON : store.cliDir(name).appendingPathComponent(".claude.json")
    }

    private func desktopData(_ name: String) -> URL {
        store.desktopDir(name) ?? paths.defaultDesktopDir
    }

    // MARK: - Claude Code history

    /// Point an account's history folders at the root account's. Sessions
    /// the account already had are moved in first, so nothing is lost.
    func linkHistory(_ name: String, to root: String) throws -> [String] {
        var notes: [String] = []
        for folder in Self.historyFolders {
            let shared = store.cliDir(root).appendingPathComponent(folder)
            let own = store.cliDir(name).appendingPathComponent(folder)
            if !isDirectory(shared) {
                // The default account's folders are never created or changed
                // by Switchboard; another account's can be.
                guard root != Profile.defaultName else { continue }
                try fm.createDirectory(at: shared, withIntermediateDirectories: true)
            }
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

    /// Stop sharing: remove the links. The shared sessions stay where they
    /// are, and this account starts a fresh folder when next used.
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

    /// Copy `source`'s MCP servers into `name`'s settings file. Servers the
    /// account added itself are kept; on a name clash the source's version
    /// wins. Returns true if the file changed.
    @discardableResult
    func syncConnectors(_ name: String, from source: String) throws -> Bool {
        try mergeServers(from: cliJSON(source), into: cliJSON(name))
    }

    /// Merge the "mcpServers" entry of one JSON file into another, leaving
    /// every other entry of the target as it was.
    private func mergeServers(from source: URL, into target: URL) throws -> Bool {
        guard let wanted = Self.object(source)?[Self.serversKey] as? [String: Any], !wanted.isEmpty else { return false }
        var document = Self.object(target) ?? [:]
        let current = document[Self.serversKey] as? [String: Any] ?? [:]
        let merged = current.merging(wanted) { _, fromSource in fromSource }
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

    /// Get an account's Claude Desktop ready to start: copy in its source
    /// account's extensions, and, when it shares Claude Code history, the
    /// main account's Code tab list. Call this just before the account's
    /// Claude Desktop starts, never while it is running. Returns true if
    /// anything was copied.
    public func prepareDesktop(_ name: String) throws -> Bool {
        guard name != Profile.defaultName, let target = store.desktopDir(name) else { return false }
        var changed = false
        if let source = self.source(.extensions, for: name) {
            changed = try copyExtensions(from: desktopData(source), to: target) || changed
        }
        if self.source(.history, for: name) != nil {
            changed = try copyCodeSessions(from: desktopData(historyRoot(of: name)), to: target) || changed
        }
        return changed
    }

    private func copyExtensions(from: URL, to target: URL) throws -> Bool {
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        var changed = try mergeServers(from: from.appendingPathComponent(Self.desktopConfig),
                                       into: target.appendingPathComponent(Self.desktopConfig))

        let registry = from.appendingPathComponent(Self.extensionRegistry)
        guard fm.fileExists(atPath: registry.path) else { return changed }
        let upToDate = fm.contentsEqual(atPath: registry.path, andPath: target.appendingPathComponent(Self.extensionRegistry).path)
            && Self.extensionItems.allSatisfy { item in
                !fm.fileExists(atPath: from.appendingPathComponent(item).path)
                    || fm.fileExists(atPath: target.appendingPathComponent(item).path)
            }
        guard !upToDate else { return changed }
        for item in Self.extensionItems {
            let source = from.appendingPathComponent(item), destination = target.appendingPathComponent(item)
            guard fm.fileExists(atPath: source.path) else { continue }
            try? fm.removeItem(at: destination)
            try fm.copyItem(at: source, to: destination)  // on APFS this shares storage until either copy changes
            changed = true
        }
        return changed
    }

    // MARK: - Claude Desktop's Code tab list (experimental)

    /// Claude Desktop lists Code sessions from its own folder, one small
    /// "local_<id>.json" entry per session, filed under the signed-in
    /// account: claude-code-sessions/<account id>/<organisation id>/. The
    /// conversations themselves are in the shared history, so copying the
    /// entries makes them show up. Experimental: this is Claude Desktop's
    /// own, undocumented layout. Entries are only ever added or refreshed,
    /// the newer copy wins, and sessions deleted on either side stay deleted.
    private func copyCodeSessions(from source: URL, to target: URL) throws -> Bool {
        let entries = codeSessionEntries(from: source, to: target).filter(\.needed)
        for entry in entries {
            try? fm.removeItem(at: entry.to)
            try fm.copyItem(at: entry.from, to: entry.to)  // keeps the date, so an unchanged entry is not copied again
        }
        return !entries.isEmpty
    }

    /// How many sessions the account's Code tab will gain the next time its
    /// Claude Desktop starts. Only new sessions count, not updated ones.
    /// Reads file names and dates only.
    public func pendingCodeSessions(_ name: String) -> Int {
        guard name != Profile.defaultName, self.source(.history, for: name) != nil,
              let target = store.desktopDir(name) else { return 0 }
        return codeSessionEntries(from: desktopData(historyRoot(of: name)), to: target)
            .filter { $0.needed && !fm.fileExists(atPath: $0.to.path) }.count
    }

    /// Every session entry in the source list, where it would go in the
    /// account's own list, and whether it needs copying there.
    private func codeSessionEntries(from source: URL, to target: URL) -> [(from: URL, to: URL, needed: Bool)] {
        guard let destination = Self.listFolders(in: target.appendingPathComponent(Self.codeSessions), fm)
            .max(by: { Self.modified($0, fm) < Self.modified($1, fm) }) else { return [] }  // Code tab never opened
        let deletedHere = Self.deletedIDs(in: destination, fm)
        return Self.listFolders(in: source.appendingPathComponent(Self.codeSessions), fm).flatMap { folder in
            let deletedThere = Self.deletedIDs(in: folder, fm)
            return ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).compactMap { entry -> (from: URL, to: URL, needed: Bool)? in
                guard let id = Self.sessionID(entry), !deletedThere.contains(id), !deletedHere.contains(id) else { return nil }
                let from = folder.appendingPathComponent(entry), to = destination.appendingPathComponent(entry)
                let needed = !fm.fileExists(atPath: to.path) || Self.modified(to, fm) < Self.modified(from, fm)
                return (from, to, needed)
            }
        }
    }

    static let codeSessions = "claude-code-sessions"

    /// "local_<id>.json" -> "<id>"; nil for anything else in the folder.
    static func sessionID(_ entry: String) -> String? {
        guard entry.hasPrefix("local_"), entry.hasSuffix(".json") else { return nil }
        return String(entry.dropFirst("local_".count).dropLast(".json".count))
    }

    private static func deletedIDs(in folder: URL, _ fm: FileManager) -> Set<String> {
        Set(((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasPrefix("deleted_") }.map { String($0.dropFirst("deleted_".count)) })
    }

    /// The <account id>/<organisation id> folders under a Code session list.
    private static func listFolders(in root: URL, _ fm: FileManager) -> [URL] {
        func folders(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).map { url.appendingPathComponent($0) }.filter {
                var isFolder: ObjCBool = false
                return fm.fileExists(atPath: $0.path, isDirectory: &isFolder) && isFolder.boolValue
            }
        }
        return folders(root).flatMap(folders)
    }

    private static func modified(_ url: URL, _ fm: FileManager) -> Date {
        ((try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? .distantPast
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
