import Foundation

/// Creates, lists and removes accounts on disk. Each account gets its own
/// Claude Code folder and Claude Desktop data folder; shared items (rules,
/// agents, skills…) are links back to the default Claude Code folder.
public struct AccountStore: Sendable {
    public let paths: Paths
    public init(paths: Paths = .live) { self.paths = paths }

    public static let pinFileName = ".claude-profile"

    /// Items every account links to, so they stay in one place. Sign-in
    /// (`.claude.json`), history and projects are never shared.
    public static let sharedItems = [
        "CLAUDE.md", "AGENTS.md", "settings.json", "keybindings.json",
        "rules", "agents", "commands", "skills", "hooks", "output-styles", "plugins",
    ]

    private var fm: FileManager { .default }

    // MARK: - Locations

    func accountDir(_ name: String) -> URL { paths.profilesHome.appendingPathComponent(name) }

    public func cliDir(_ name: String) -> URL {
        name == Profile.defaultName ? paths.defaultCLIDir : accountDir(name).appendingPathComponent("cli")
    }

    /// Nil for the default account, which uses Claude Desktop's normal folder.
    public func desktopDir(_ name: String) -> URL? {
        name == Profile.defaultName ? nil : accountDir(name).appendingPathComponent("desktop")
    }

    private func iconFile(_ name: String) -> URL {
        name == Profile.defaultName ? paths.profilesHome.appendingPathComponent(".default-icon")
                                    : accountDir(name).appendingPathComponent("icon")
    }

    // MARK: - Reading

    public func exists(_ name: String) -> Bool {
        if name == Profile.defaultName { return true }
        var isDir: ObjCBool = false
        return ProfileName.isValid(name) && fm.fileExists(atPath: accountDir(name).path, isDirectory: &isDir)
            && isDir.boolValue
    }

    /// Throws a plain-words error unless `name` is an existing account.
    public func require(_ name: String) throws {
        guard ProfileName.isValid(name) else {
            throw SwitchboardError("invalid account name '\(name)' (use a-z, 0-9, '-', '_'; max \(ProfileName.maxLength) characters)")
        }
        guard exists(name) else { throw SwitchboardError("no account '\(name)' (create it: cprof add \(name))") }
    }

    /// "default" first, then the others by name.
    public func names() -> [String] {
        let found = (try? fm.contentsOfDirectory(atPath: paths.profilesHome.path)) ?? []
        return [Profile.defaultName] + found.filter { $0 != Profile.defaultName && exists($0) }.sorted()
    }

    public func profiles() -> [Profile] { names().map(profile) }

    public func profile(_ name: String) -> Profile {
        Profile(name: name, email: codeEmail(name), desktopSignedIn: desktopSignedIn(name),
                cliDir: cliDir(name).path, desktopDir: desktopDir(name)?.path ?? "", icon: icon(name))
    }

    /// The email Claude Code is signed in with, read from its own state file.
    func codeEmail(_ name: String) -> String {
        let file = name == Profile.defaultName ? paths.defaultCLIJSON : cliDir(name).appendingPathComponent(".claude.json")
        let account = Self.json(file)?["oauthAccount"] as? [String: Any]
        return (account?["emailAddress"] as? String) ?? ""
    }

    /// True once Claude Desktop has saved an account id. Reads no tokens.
    func desktopSignedIn(_ name: String) -> Bool {
        let dir = desktopDir(name) ?? paths.defaultDesktopDir
        let id = Self.json(dir.appendingPathComponent("config.json"))?["lastKnownAccountUuid"] as? String
        return !(id ?? "").isEmpty
    }

    func icon(_ name: String) -> String? {
        guard let text = try? String(contentsOf: iconFile(name), encoding: .utf8) else { return nil }
        let symbol = text.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return AccountIcon.isValid(symbol) ? symbol : nil
    }

    private static func json(_ file: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Changing

    @discardableResult
    public func add(_ name: String) throws -> Profile {
        guard ProfileName.isValid(name) else {
            throw SwitchboardError("invalid account name '\(name)' (use a-z, 0-9, '-', '_'; max \(ProfileName.maxLength) characters)")
        }
        guard name != Profile.defaultName else { throw SwitchboardError("'default' always exists") }
        guard !exists(name) else { throw SwitchboardError("account '\(name)' already exists") }
        let privateDir: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        try fm.createDirectory(at: accountDir(name), withIntermediateDirectories: true, attributes: privateDir)
        try fm.createDirectory(at: cliDir(name), withIntermediateDirectories: true)
        if let desktop = desktopDir(name) { try fm.createDirectory(at: desktop, withIntermediateDirectories: true) }
        linkShared(name)
        return profile(name)
    }

    /// Link shared items into an account. An item the account has replaced
    /// with its own real file is left alone; those are returned.
    @discardableResult
    public func linkShared(_ name: String) -> [String] {
        guard name != Profile.defaultName else { return [] }
        var keptOwn: [String] = []
        for item in Self.sharedItems {
            let source = paths.defaultCLIDir.appendingPathComponent(item)
            let link = cliDir(name).appendingPathComponent(item)
            guard fm.fileExists(atPath: source.path) else { continue }
            if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil {
                try? fm.removeItem(at: link)
            } else if fm.fileExists(atPath: link.path) {
                keptOwn.append(item)
                continue
            }
            try? fm.createSymbolicLink(at: link, withDestinationURL: source)
        }
        return keptOwn
    }

    /// Delete an account's folders. Signing out and quitting Claude are the
    /// caller's job, because they involve other programs.
    public func remove(_ name: String) throws {
        try require(name)
        guard name != Profile.defaultName else { throw SwitchboardError("refusing to delete the default account") }
        try fm.removeItem(at: accountDir(name))
        try? fm.removeItem(at: paths.launchDir.appendingPathComponent("\(name).command"))
    }

    /// Set an account's icon; nil or empty clears it.
    public func setIcon(_ name: String, to symbol: String?) throws {
        try require(name)
        let file = iconFile(name)
        guard let symbol, !symbol.isEmpty else { try? fm.removeItem(at: file); return }
        guard AccountIcon.isValid(symbol) else {
            throw SwitchboardError("invalid icon '\(symbol)' (use a system symbol name like briefcase or house.fill)")
        }
        try fm.createDirectory(at: paths.profilesHome, withIntermediateDirectories: true)
        try (symbol + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - Which account a command uses

    public enum Source: Equatable, Sendable {
        case explicit, environment, folderFile(URL), fallback
    }

    public struct Resolution: Equatable, Sendable {
        public let name: String
        public let source: Source
    }

    /// A name typed on the command line wins, then `$CPROF_PROFILE`, then
    /// the nearest `.claude-profile` file walking up from `cwd`, then default.
    public func resolve(explicit: String?, environment: [String: String], cwd: URL) -> Resolution {
        if let explicit, !explicit.isEmpty { return Resolution(name: explicit, source: .explicit) }
        if let fromEnv = environment["CPROF_PROFILE"], !fromEnv.isEmpty {
            return Resolution(name: fromEnv, source: .environment)
        }
        // Plain path strings: "/" is its own parent, so the walk always ends.
        var dir = cwd.standardizedFileURL.path
        while true {
            let file = URL(fileURLWithPath: dir).appendingPathComponent(Self.pinFileName)
            if let text = try? String(contentsOf: file, encoding: .utf8),
               let first = text.split(whereSeparator: \.isNewline).first {
                let name = first.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return Resolution(name: name, source: .folderFile(file)) }
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { break }
            dir = parent
        }
        return Resolution(name: Profile.defaultName, source: .fallback)
    }

    /// Pin a folder to an account by writing its `.claude-profile` file.
    public func pin(_ name: String, in folder: URL) throws {
        try require(name)
        try (name + "\n").write(to: folder.appendingPathComponent(Self.pinFileName), atomically: true, encoding: .utf8)
    }

    /// Shell lines that switch the current shell to an account.
    public func shellExports(_ name: String) -> String {
        let profile = "export CPROF_PROFILE=\(Shell.quote(name))\n"
        if name == Profile.defaultName { return profile + "unset CLAUDE_CONFIG_DIR" }
        return profile + "export CLAUDE_CONFIG_DIR=\(Shell.quote(cliDir(name).path))"
    }
}
