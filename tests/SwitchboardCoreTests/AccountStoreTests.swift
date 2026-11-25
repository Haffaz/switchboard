import Foundation
import Testing
@testable import SwitchboardCore

/// A throwaway home folder with a default Claude Code setup in it.
final class Sandbox {
    let home: URL
    let store: AccountStore
    private let fm = FileManager.default

    init(profilesFolder: String = ".claude-profiles") throws {
        home = fm.temporaryDirectory.appendingPathComponent("switchboard-tests-\(UUID().uuidString)")
        let paths = Paths(home: home, profilesHome: home.appendingPathComponent(profilesFolder))
        store = AccountStore(paths: paths)
        try fm.createDirectory(at: paths.defaultCLIDir.appendingPathComponent("rules"), withIntermediateDirectories: true)
        try "# shared".write(to: paths.defaultCLIDir.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
    }

    deinit { try? fm.removeItem(at: home) }

    func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func linkTarget(_ url: URL) -> String? { try? fm.destinationOfSymbolicLink(atPath: url.path) }
    func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }
}

@Suite("Adding and removing accounts")
struct AccountLifecycleTests {
    @Test("Add creates both folders and links shared items, but never sign-in")
    func addCreatesLayout() throws {
        let box = try Sandbox()
        let profile = try box.store.add("work")
        let cli = box.store.cliDir("work")
        #expect(box.exists(cli) && box.exists(box.store.desktopDir("work")!))
        #expect(box.linkTarget(cli.appendingPathComponent("CLAUDE.md")) == box.store.paths.defaultCLIDir.appendingPathComponent("CLAUDE.md").path)
        #expect(box.linkTarget(cli.appendingPathComponent("rules")) == box.store.paths.defaultCLIDir.appendingPathComponent("rules").path)
        #expect(!box.exists(cli.appendingPathComponent(".claude.json")))
        #expect(profile.desktopDir == box.store.desktopDir("work")!.path)
    }

    @Test("The account folder is private to the user")
    func folderIsPrivate() throws {
        let box = try Sandbox()
        try box.store.add("work")
        let mode = try FileManager.default.attributesOfItem(atPath: box.store.accountDir("work").path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
    }

    @Test("Bad names are refused", arguments: ["Bad Name", "../x", "", "-lead", "UPPER", String(repeating: "a", count: 33)])
    func rejectsBadNames(name: String) throws {
        let box = try Sandbox()
        #expect(throws: SwitchboardError.self) { try box.store.add(name) }
        #expect(box.store.names() == ["default"])
    }

    @Test("'default' and duplicates are refused")
    func rejectsDefaultAndDuplicates() throws {
        let box = try Sandbox()
        #expect(throws: SwitchboardError("'default' always exists")) { try box.store.add("default") }
        try box.store.add("work")
        #expect(throws: SwitchboardError("account 'work' already exists")) { try box.store.add("work") }
    }

    @Test("Re-linking keeps a file the account replaced with its own")
    func linkKeepsOverride() throws {
        let box = try Sandbox()
        try box.store.add("work")
        let own = box.store.cliDir("work").appendingPathComponent("CLAUDE.md")
        try FileManager.default.removeItem(at: own)
        try box.write("# own", to: own)
        #expect(box.store.linkShared("work") == ["CLAUDE.md"])
        #expect(try String(contentsOf: own, encoding: .utf8) == "# own")
    }

    @Test("Remove deletes the account but refuses the default")
    func remove() throws {
        let box = try Sandbox()
        try box.store.add("work")
        try box.store.remove("work")
        #expect(!box.exists(box.store.accountDir("work")))
        #expect(throws: SwitchboardError.self) { try box.store.remove("default") }
        #expect(throws: SwitchboardError.self) { try box.store.remove("ghost") }
    }

    @Test("Listing puts default first and ignores stray files")
    func listing() throws {
        let box = try Sandbox()
        try box.store.add("zeta")
        try box.store.add("alpha")
        try box.write("x", to: box.store.paths.profilesHome.appendingPathComponent(".launch/alpha.command"))
        try box.write("x", to: box.store.paths.profilesHome.appendingPathComponent("Not A Profile/file"))
        #expect(box.store.names() == ["default", "alpha", "zeta"])
    }
}

@Suite("What is known about an account")
struct AccountDetailTests {
    @Test("Reads the Claude Code email and Desktop sign-in from Claude's own files")
    func readsSignIn() throws {
        let box = try Sandbox()
        try box.store.add("work")
        #expect(box.store.profile("work").email.isEmpty)
        #expect(!box.store.profile("work").desktopSignedIn)

        try box.write(#"{"oauthAccount":{"emailAddress":"me@work.example"}}"#,
                      to: box.store.cliDir("work").appendingPathComponent(".claude.json"))
        try box.write(#"{"lastKnownAccountUuid":"abc"}"#,
                      to: box.store.desktopDir("work")!.appendingPathComponent("config.json"))
        let profile = box.store.profile("work")
        #expect(profile.email == "me@work.example" && profile.desktopSignedIn)
    }

    @Test("The default account reads from the usual places")
    func defaultAccount() throws {
        let box = try Sandbox()
        try box.write(#"{"oauthAccount":{"emailAddress":"me@home.example"}}"#, to: box.store.paths.defaultCLIJSON)
        let profile = box.store.profile("default")
        #expect(profile.email == "me@home.example")
        #expect(profile.desktopDir.isEmpty && profile.cliDir == box.store.paths.defaultCLIDir.path)
    }

    @Test("Broken or odd JSON never crashes the listing", arguments: ["", "not json", "[]", #"{"oauthAccount":7}"#])
    func survivesBadJSON(contents: String) throws {
        let box = try Sandbox()
        try box.store.add("work")
        try box.write(contents, to: box.store.cliDir("work").appendingPathComponent(".claude.json"))
        #expect(box.store.profile("work").email.isEmpty)
    }

    @Test("Icons can be set, cleared, and are checked")
    func icons() throws {
        let box = try Sandbox()
        try box.store.add("work")
        try box.store.setIcon("work", to: "briefcase.fill")
        try box.store.setIcon("default", to: "house")
        #expect(box.store.profile("work").icon == "briefcase.fill")
        #expect(box.store.profile("default").icon == "house")
        #expect(throws: SwitchboardError.self) { try box.store.setIcon("work", to: "bad icon; rm -rf") }
        try box.store.setIcon("work", to: nil)
        #expect(box.store.profile("work").icon == nil)
        #expect(box.store.names() == ["default", "work"])  // the default's icon file is not an account
    }
}

@Suite("Claude Code login, as Claude Code reports it")
struct CodeLoginTests {
    @Test("Reads signed-in and signed-out answers")
    func parses() {
        let signedIn = ClaudeCode.parseLoginStatus(Data(#"{"loggedIn":true,"authMethod":"claude.ai","email":"me@x.example"}"#.utf8))
        #expect(signedIn == CodeLogin(signedIn: true, email: "me@x.example"))
        let signedOut = ClaudeCode.parseLoginStatus(Data(#"{"loggedIn":false,"authMethod":"none"}"#.utf8))
        #expect(signedOut == CodeLogin(signedIn: false, email: ""))
    }

    @Test("Anything unexpected means 'could not ask', not 'signed out'", arguments: ["", "not json", "[]", #"{"loggedIn":"yes"}"#])
    func rejectsGarbage(output: String) {
        #expect(ClaudeCode.parseLoginStatus(Data(output.utf8)) == nil)
    }

    @Test("A leftover email in the settings file does not count as signed in")
    func staleEmailIsCleared() throws {
        let box = try Sandbox()
        try box.store.add("work")
        try box.write(#"{"oauthAccount":{"emailAddress":"old@x.example"}}"#,
                      to: box.store.cliDir("work").appendingPathComponent(".claude.json"))
        let guess = box.store.profile("work")
        #expect(guess.codeSignedIn)  // the fast guess is fooled
        let corrected = guess.applying(CodeLogin(signedIn: false, email: ""))
        #expect(!corrected.codeSignedIn && corrected.email.isEmpty)
        #expect(corrected.icon == guess.icon && corrected.desktopDir == guess.desktopDir)
    }

    @Test("A real login wins, and supplies the email")
    func realLoginWins() {
        let guess = Profile(name: "work", email: "", desktopSignedIn: true, cliDir: "", desktopDir: "/d")
        #expect(guess.applying(CodeLogin(signedIn: true, email: "me@x.example")).email == "me@x.example")
        #expect(guess.applying(CodeLogin(signedIn: true, email: "")).codeSignedIn)
    }
}

@Suite("Which account a command uses")
struct ResolutionTests {
    @Test("A typed name wins, then the environment, then the folder's file, then default")
    func order() throws {
        let box = try Sandbox()
        let repo = box.home.appendingPathComponent("repo")
        let sub = repo.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        #expect(box.store.resolve(explicit: nil, environment: [:], cwd: sub).source == .fallback)
        try box.write("personal\n", to: repo.appendingPathComponent(".claude-profile"))
        let fromFile = box.store.resolve(explicit: nil, environment: [:], cwd: sub)
        #expect(fromFile.name == "personal")
        #expect(fromFile.source == .folderFile(repo.appendingPathComponent(".claude-profile").standardizedFileURL))

        let fromEnv = box.store.resolve(explicit: nil, environment: ["CPROF_PROFILE": "work"], cwd: sub)
        #expect(fromEnv == .init(name: "work", source: .environment))
        let typed = box.store.resolve(explicit: "other", environment: ["CPROF_PROFILE": "work"], cwd: sub)
        #expect(typed == .init(name: "other", source: .explicit))
    }

    @Test("An empty file or empty variable is ignored")
    func ignoresEmpty() throws {
        let box = try Sandbox()
        try box.write("  \n", to: box.home.appendingPathComponent(".claude-profile"))
        let result = box.store.resolve(explicit: "", environment: ["CPROF_PROFILE": ""], cwd: box.home)
        #expect(result.name == "default")
    }

    @Test("Pinning a folder writes the file that resolve reads")
    func pin() throws {
        let box = try Sandbox()
        try box.store.add("work")
        try box.store.pin("work", in: box.home)
        #expect(box.store.resolve(explicit: nil, environment: [:], cwd: box.home).name == "work")
        #expect(throws: SwitchboardError.self) { try box.store.pin("ghost", in: box.home) }
    }

    @Test("Shell exports switch the config folder, or clear it for default")
    func shellExports() throws {
        let box = try Sandbox(profilesFolder: "my profiles")
        try box.store.add("work")
        #expect(box.store.shellExports("work") ==
                "export CPROF_PROFILE='work'\nexport CLAUDE_CONFIG_DIR='\(box.store.cliDir("work").path)'")
        #expect(box.store.shellExports("default") == "export CPROF_PROFILE='default'\nunset CLAUDE_CONFIG_DIR")
    }
}

@Suite("Launchers")
struct LauncherTests {
    @Test("Shell quoting survives quotes and spaces", arguments: [
        ("plain", "'plain'"), ("two words", "'two words'"), ("it's", #"'it'\''s'"#), ("", "''"),
    ])
    func quoting(value: String, expected: String) {
        #expect(Shell.quote(value) == expected)
    }

    @Test("Terminal script sets the account, then runs the right thing")
    func terminalScript() {
        let exports = "export CPROF_PROFILE='work'\nexport CLAUDE_CONFIG_DIR='/p/work/cli'"
        let signIn = TerminalLauncher.script(name: "work", exports: exports, fallbackClaude: "/opt/claude", mode: .signIn)
        #expect(signIn.hasPrefix("#!/bin/zsh -li\n"))
        #expect(signIn.contains(exports) && signIn.contains("fallback='/opt/claude'"))
        #expect(signIn.contains("\nrun_claude auth login\n"))
        let code = TerminalLauncher.script(name: "work", exports: exports, fallbackClaude: nil, mode: .claudeCode)
        #expect(code.contains("\ncd ~ && run_claude\n") && code.contains("fallback=''"))
        let shell = TerminalLauncher.script(name: "work", exports: exports, fallbackClaude: nil, mode: .shell)
        #expect(!shell.contains("\nrun_claude auth") && !shell.contains("cd ~ && run_claude"))
        #expect(shell.hasSuffix("exec \"$SHELL\" -l\n"))
    }

    @Test("Dock launcher is a small app that calls cprof for that account")
    func dockLauncher() throws {
        let box = try Sandbox()
        try box.store.add("work")
        let app = try DockLauncher.make("work", cprof: URL(fileURLWithPath: "/Apps/My App/cprof"), claudeApp: nil, store: box.store)
        #expect(app.path == box.home.appendingPathComponent("Applications/Claude (work).app").path)
        let launch = app.appendingPathComponent("Contents/MacOS/launch")
        #expect(try String(contentsOf: launch, encoding: .utf8) == "#!/bin/sh\nexec '/Apps/My App/cprof' desktop 'work'\n")
        #expect(FileManager.default.isExecutableFile(atPath: launch.path))
        #expect(throws: SwitchboardError.self) {
            try DockLauncher.make("ghost", cprof: URL(fileURLWithPath: "/x"), claudeApp: nil, store: box.store)
        }
    }
}
