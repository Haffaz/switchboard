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
          add <name>             Create an account (shares rules/agents/skills with ~/.claude)
          rm <name> [--yes]      Sign out and delete an account and its data
          icon <name> [symbol]   Set an account's menu icon (e.g. briefcase); no symbol clears it

          cli [name] [-- args]   Run `claude` as an account
          desktop [name]         Open Claude Desktop as an account
          code [name]            Open a Terminal window running Claude Code
          login [name]           Open a Terminal window that signs Claude Code in
          terminal [name]        Open a Terminal window set to an account

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
        case "add": try add(try name(args, usage: "cprof add <name>"))
        case "rm", "remove": try remove(try name(args, usage: "cprof rm <name>"), confirmed: args.contains("--yes"))
        case "icon": try icon(try name(args, usage: "cprof icon <name> [symbol]"), args.count > 1 ? args[1] : nil)
        case "cli", "run": try runClaude(args)
        case "desktop": try await ClaudeDesktop.open(store.profile(try resolve(args.first)))
        case "code": try TerminalLauncher.open(try resolve(args.first), mode: .claudeCode, store: store)
        case "login": try TerminalLauncher.open(try resolve(args.first), mode: .signIn, store: store)
        case "terminal", "term": try TerminalLauncher.open(try resolve(args.first), mode: .shell, store: store)
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
        let icon: String?
        let desktopRunning, desktopSignedIn: Bool
        let cliDir, desktopDir: String
    }

    private func list(json: Bool) throws {
        let profiles = store.profiles()
        if json {
            let entries = profiles.map {
                ListEntry(name: $0.name, email: $0.email, icon: $0.icon,
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
            let padded = profile.name.padding(toLength: 16, withPad: " ", startingAt: 0)
            print("\(mark) \(padded) \(profile.email.isEmpty ? "(not signed in)" : profile.email)")
        }
    }

    private func add(_ rawName: String) throws {
        try store.add(rawName)
        print("""
            Created \(rawName). Sign in with:
              cprof login \(rawName)      (Claude Code)
              cprof desktop \(rawName)    (Claude Desktop)
            """)
    }

    private func remove(_ name: String, confirmed: Bool) throws {
        try store.require(name)
        guard name != Profile.defaultName else { throw SwitchboardError("refusing to delete the default account") }
        let profile = store.profile(name)
        if !confirmed {
            print("Delete account '\(name)' and all its data? [y/N] ", terminator: "")
            guard let reply = readLine(), reply.lowercased() == "y" else { print("Cancelled."); return }
        }
        guard ClaudeDesktop.running(profile) == nil else {
            throw SwitchboardError("quit Claude Desktop for '\(name)' first")
        }
        let signedOut = !profile.codeSignedIn || ClaudeCode.signOut(configDir: store.cliDir(name))
        try store.remove(name)
        print("Deleted \(name).")
        if !signedOut { print(Self.signOutFailedNote) }
    }

    static let signOutFailedNote = "Its Claude Code sign-in could not be removed from Keychain. "
        + "Open Keychain Access and delete the newest \"Claude Code-credentials\" entry if you want it gone."

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
