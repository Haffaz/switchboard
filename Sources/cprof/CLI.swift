import Foundation
import SwitchboardCore

/// The `cprof` command. A thin layer: it reads arguments, calls the shared
/// core, and prints. Every rule lives in SwitchboardCore.
@MainActor
struct CLI {
    let store = AccountStore()
    let environment = ProcessInfo.processInfo.environment
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    static let usage = """
        Usage: cprof <command> [args]

          list [--json]          List accounts and who is signed in (the default command)
          add <name> [--separate]
                                 Create an account; "add My Work" is shown as My Work, used as my-work.
                                 It shares history, connectors and extensions with Default unless --separate
          rm <name> [--yes]      Sign out and delete an account and its data
          rename <name> [label]  Change the name shown for an account; no label resets it
          icon <name> [symbol]   Set an account's menu icon (e.g. briefcase); no symbol clears it

          cli [name] [-- args]   Run `claude` as an account
          continue <name> [-- args]
                                 Continue this folder's latest Claude Code conversation as another account
          desktop [name]         Open Claude Desktop as an account
          code [name]            Open a Terminal window running Claude Code
          login [name]           Open a Terminal window that signs Claude Code in
          terminal [name]        Open a Terminal window set to an account

          share                  Show who shares what with whom
          share <name> <thing> <from|off>
                                 Share history, connectors or extensions from another account
          sync                   Apply sharing now (copy connectors, link history)

          use <name>             Pin this folder to an account (writes .claude-profile)
          which                  Print the account this folder resolves to
          env [name]             Print shell exports; use: eval "$(cprof env work)"
          init zsh|bash          Print a snippet that makes `claude` follow the folder's account
          link <name>            Re-link shared items from ~/.claude into an account
          app <name>             Make "Claude (<name>).app" in ~/Applications for the Dock
          install-cli            Put cprof on your PATH (~/.local/bin)

        When [name] is omitted: $CPROF_PROFILE, then the nearest .claude-profile
        file, then "default".
        """

    func run(_ arguments: [String]) async throws {
        var args = arguments
        let command = args.isEmpty ? "list" : args.removeFirst()
        switch command {
        case "list", "ls": try list(json: args.first == "--json")
        case "add": try add(args)
        case "rm", "remove": try remove(try name(args, usage: "cprof rm <name>"), confirmed: args.contains("--yes"))
        case "rename": try rename(try name(args, usage: "cprof rename <name> [label]"), Array(args.dropFirst()))
        case "icon": try icon(try name(args, usage: "cprof icon <name> [symbol]"), args.count > 1 ? args[1] : nil)
        case "cli", "run": try runClaude(args)
        case "continue": try continueAs(args)
        case "desktop": try await ClaudeDesktop.open(store.profile(try resolve(args.first)))
        case "code": try TerminalLauncher.open(try resolve(args.first), mode: .claudeCode, store: store)
        case "login": try TerminalLauncher.open(try resolve(args.first), mode: .signIn, store: store)
        case "terminal", "term": try TerminalLauncher.open(try resolve(args.first), mode: .shell, store: store)
        case "share": try share(args)
        case "sync": try sync()
        case "use": try use(try name(args, usage: "cprof use <name>"))
        case "which": print(store.resolve(explicit: nil, environment: environment, cwd: cwd).name)
        case "env": print(store.shellExports(try resolve(args.first)))
        case "init": try printInit(args.first)
        case "link": try link(try name(args, usage: "cprof link <name>"))
        case "app": try makeDockApp(try name(args, usage: "cprof app <name>"))
        case "install-cli": try installCLI()
        case "help", "-h", "--help": print(Self.usage)
        default: throw SwitchboardError("unknown command '\(command)'\n\n\(Self.usage)")
        }
    }

    // MARK: - Helpers

    private func name(_ args: [String], usage: String) throws -> String {
        guard let first = args.first, !first.hasPrefix("-") else { throw SwitchboardError("usage: \(usage)") }
        return first
    }

    /// The account to use when the name is optional.
    private func resolve(_ explicit: String?) throws -> String {
        let name = store.resolve(explicit: explicit, environment: environment, cwd: cwd).name
        try store.require(name)
        return name
    }

    private var ownPath: URL {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    }

    // MARK: - Commands

    private struct ListEntry: Encodable {
        let name, email: String
        let icon, label: String?
        let desktopRunning, desktopSignedIn: Bool
        let cliDir, desktopDir: String
    }

    private func list(json: Bool) throws {
        let profiles = store.verifiedProfiles()
        if json {
            let entries = profiles.map {
                ListEntry(name: $0.name, email: $0.email, icon: $0.icon, label: $0.label,
                          desktopRunning: ClaudeDesktop.running($0) != nil, desktopSignedIn: $0.desktopSignedIn,
                          cliDir: $0.cliDir, desktopDir: $0.desktopDir)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(entries), as: UTF8.self))
            return
        }
        let current = store.resolve(explicit: nil, environment: environment, cwd: cwd).name
        for profile in profiles {
            let mark = profile.name == current ? "*" : " "
            let shown = profile.label.map { "\(profile.name) (\($0))" } ?? profile.name
            let padded = shown.count >= 24 ? shown + " " : shown.padding(toLength: 24, withPad: " ", startingAt: 0)
            let email = profile.email.isEmpty ? "(not signed in)" : profile.email
            print("\(mark) \(padded) \(email)\(profile.isDefault ? "   main account" : "")")
        }
    }

    /// `cprof add Work Stuff` makes the account `work-stuff`, shown as "Work Stuff".
    private func add(_ words: [String]) throws {
        let separate = words.contains("--separate")
        let nameWords = words.filter { $0 != "--separate" }
        guard !nameWords.isEmpty, !nameWords[0].hasPrefix("-") else {
            throw SwitchboardError("usage: cprof add <name> [--separate]")
        }
        let profile = try store.create(nameWords.joined(separator: " "))
        if separate {
            try Sharing(store: store).apply()
        } else {
            try Sharing(store: store).setSameAsDefault(profile.name, true)
        }
        let shown = profile.label.map { " (shown as \($0))" } ?? ""
        let sharing = separate ? "It shares only rules, skills, plugins and settings."
                               : "It shares history, connectors and extensions with default."
        print("""
            Created \(profile.name)\(shown). \(sharing)
            Sign in with:
              cprof login \(profile.name)      (Claude Code)
              cprof desktop \(profile.name)    (Claude Desktop)
            """)
    }

    private func remove(_ name: String, confirmed: Bool) throws {
        try store.require(name)
        guard name != Profile.defaultName else { throw SwitchboardError("refusing to delete the default account") }
        let profile = store.verifiedProfiles().first { $0.name == name } ?? store.profile(name)
        if !confirmed {
            print("Delete account '\(name)' and all its data? [y/N] ", terminator: "")
            guard let reply = readLine(), reply.lowercased() == "y" else { print("Cancelled."); return }
        }
        guard ClaudeDesktop.running(profile) == nil else {
            throw SwitchboardError("quit Claude Desktop for '\(name)' first")
        }
        let sharers = Sharing(store: store).historySharers(of: name)
        guard sharers.isEmpty else {
            throw SwitchboardError("Claude Code history for \(sharers.joined(separator: ", ")) lives in '\(name)'; "
                                   + "stop sharing it first (cprof share <name> history off)")
        }
        let signedOut = !profile.codeSignedIn || ClaudeCode.signOut(configDir: store.cliDir(name))
        try store.remove(name)
        try Sharing(store: store).forget(name)
        print("Deleted \(name).")
        if !signedOut { print(Self.signOutFailedNote) }
    }

    static let signOutFailedNote = "Its Claude Code sign-in could not be removed from Keychain. "
        + "Open Keychain Access and delete the newest \"Claude Code-credentials\" entry if you want it gone."

    private func rename(_ name: String, _ words: [String]) throws {
        let label = words.joined(separator: " ")
        try store.setLabel(name, to: label)
        let shown = store.profile(name).displayName
        print(AccountLabel.clean(label) == nil ? "\(name) is shown as \(shown) again." : "\(name) is now shown as \(shown).")
    }

    private func icon(_ name: String, _ symbol: String?) throws {
        try store.setIcon(name, to: symbol)
        print(symbol.map { "Icon for \(name) is now \($0)." } ?? "Cleared icon for \(name).")
    }

    /// `cprof cli [name] [-- args]`: become `claude`, as that account.
    private func runClaude(_ arguments: [String]) throws {
        var args = arguments
        var explicit: String?
        if let first = args.first, first != "--", !first.hasPrefix("-") { explicit = first; args.removeFirst() }
        if args.first == "--" { args.removeFirst() }

        let resolution = store.resolve(explicit: explicit, environment: environment, cwd: cwd)
        try store.require(resolution.name)
        // A folder's .claude-profile picked the account: say so, since the
        // file may have come with a cloned repository.
        if case .folderFile = resolution.source, resolution.name != Profile.defaultName, isatty(STDERR_FILENO) != 0 {
            FileHandle.standardError.write(Data(
                "cprof: using account '\(resolution.name)' (from a \(AccountStore.pinFileName) file)\n".utf8))
        }
        guard let claude = ClaudeCode.find() else {
            throw SwitchboardError("Claude Code is not installed (see https://claude.com/claude-code)")
        }
        if resolution.name == Profile.defaultName {
            unsetenv("CLAUDE_CONFIG_DIR")
        } else {
            setenv("CLAUDE_CONFIG_DIR", store.cliDir(resolution.name).path, 1)
        }
        let argv: [UnsafeMutablePointer<CChar>?] = ([claude.path] + args).map { strdup($0) } + [nil]
        execv(claude.path, argv)
        throw SwitchboardError("could not start \(claude.path): \(String(cString: strerror(errno)))")
    }

    /// `cprof continue personal`: reopen this folder's most recent Claude Code
    /// conversation, as another account. It only finds the conversation when
    /// the two accounts share history, so say so when they do not.
    private func continueAs(_ arguments: [String]) throws {
        guard let target = arguments.first, !target.hasPrefix("-") else {
            throw SwitchboardError("usage: cprof continue <name> [-- args]")
        }
        try store.require(target)
        let sharing = Sharing(store: store)
        let current = store.resolve(explicit: nil, environment: environment, cwd: cwd).name
        if current != target, store.exists(current), sharing.historyRoot(of: target) != sharing.historyRoot(of: current) {
            FileHandle.standardError.write(Data((
                "cprof: \(target) does not share history with \(current), so this starts a new conversation.\n"
                + "cprof: to share it: cprof share \(target) history \(sharing.historyRoot(of: current))\n").utf8))
        }
        var rest = Array(arguments.dropFirst())
        if rest.first == "--" { rest.removeFirst() }
        try runClaude([target, "--", "--continue"] + rest)
    }

    /// `cprof share` shows a table; `cprof share work history default` changes it.
    private func share(_ args: [String]) throws {
        let sharing = Sharing(store: store)
        guard !args.isEmpty else {
            let sources = sharing.sources()
            let things = SharedThing.allCases
            let head = "account".padding(toLength: 18, withPad: " ", startingAt: 0)
                + things.map { $0.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0) }.joined()
            print(head.trimmingCharacters(in: .whitespaces))
            for name in store.names() where name != Profile.defaultName {
                let cells = things.map { (sources[name]?[$0] ?? "-").padding(toLength: 14, withPad: " ", startingAt: 0) }
                print((name.padding(toLength: 18, withPad: " ", startingAt: 0) + cells.joined())
                    .trimmingCharacters(in: .whitespaces))
            }
            print("\nRules, agents, skills, plugins and settings are always shared.")
            return
        }
        let names = SharedThing.allCases.map(\.rawValue).joined(separator: "|")
        guard args.count == 3, let thing = SharedThing(rawValue: args[1]) else {
            throw SwitchboardError("usage: cprof share <name> <\(names)> <from-account|off>")
        }
        let source = args[2] == "off" ? nil : args[2]
        let notes = try sharing.setSource(thing, for: args[0], to: source)
        print(source.map { "\(args[0]) now shares \(thing.rawValue) with \($0)." } ?? "\(args[0]) no longer shares \(thing.rawValue).")
        notes.forEach { print("note: \($0)") }
        if thing == .extensions, source != nil {
            print("Extensions are copied the next time \(args[0])'s Claude Desktop starts.")
        }
    }

    private func sync() throws {
        let notes = try Sharing(store: store).apply()
        notes.forEach { print("note: \($0)") }
        print("Sharing applied.")
    }

    private func use(_ name: String) throws {
        try store.pin(name, in: cwd)
        print("Pinned \(cwd.path) to '\(name)'.")
    }

    private func printInit(_ shell: String?) throws {
        guard shell == "zsh" || shell == "bash" else { throw SwitchboardError("usage: cprof init zsh|bash") }
        print("""
            # cprof: make `claude` follow the folder's account.
            claude() { command cprof cli -- "$@"; }
            cprof-use() { eval "$(command cprof env "$@")"; }
            """)
    }

    private func link(_ name: String) throws {
        try store.require(name)
        for item in store.linkShared(name) {
            FileHandle.standardError.write(Data("cprof: \(name): keeping own \(item)\n".utf8))
        }
    }

    private func makeDockApp(_ name: String) throws {
        let app = try DockLauncher.make(name, cprof: ownPath, claudeApp: ClaudeDesktop.appURL, store: store)
        print("Made \(app.path). Drag it to the Dock.")
    }

    private func installCLI() throws {
        let bin = store.paths.home.appendingPathComponent(".local/bin")
        let link = bin.appendingPathComponent("cprof")
        let fm = FileManager.default
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try? fm.removeItem(at: link)
        try fm.createSymbolicLink(at: link, withDestinationURL: ownPath)
        print("Installed \(link.path)")
        if !(environment["PATH"] ?? "").split(separator: ":").contains(Substring(bin.path)) {
            print("Add \(bin.path) to your PATH.")
        }
    }
}
