import AppKit
import ServiceManagement
import SwitchboardCore

/// Everything the app can do to an account or to itself. The menu and the
/// Settings window both call these, so they always behave the same way.
@MainActor
enum Actions {
    static let accounts = AccountStore()
    private static var store: ProfileStore { .shared }

    /// Do some work on the accounts off the main thread; show any error in
    /// plain words, then reload what the app knows. Returns false if it failed.
    @discardableResult
    static func perform(_ work: @Sendable @escaping () throws -> Void) async -> Bool {
        guard !store.isDemo else { return false }
        do {
            try await Task.detached(operation: work).value
            await store.refresh(recheckLogins: true)
            return true
        } catch {
            let text = error.localizedDescription
            Dialogs.error(text.prefix(1).uppercased() + text.dropFirst())
            return false
        }
    }

    // MARK: - Opening and quitting

    static func openDesktop(_ profile: Profile) async {
        guard !store.isDemo else { return }
        if profile.needsDesktopSignIn { await DesktopSignIn.run(profile); return }
        do { try await ClaudeDesktop.open(profile) } catch { Dialogs.error(error.localizedDescription) }
    }

    /// Opens Claude Code in a Terminal window, or signs it in first.
    static func openCode(_ profile: Profile) async {
        await openTerminal(profile, profile.codeSignedIn ? .claudeCode : .signIn)
    }

    static func openTerminal(_ profile: Profile, _ mode: TerminalLauncher.Mode) async {
        let accounts = accounts
        await perform { try TerminalLauncher.open(profile.name, mode: mode, store: accounts) }
    }

    static func signInDesktop(_ profile: Profile) async {
        guard !store.isDemo else { return }
        await DesktopSignIn.run(profile)
    }

    static func quit(_ profile: Profile) async {
        guard !store.isDemo else { return }
        Log.write("quit \(profile.name): asked")
        if await ClaudeDesktop.quit(profile) { return }
        // Claude can refuse to quit while work is running.
        if Dialogs.confirmForceQuit(profile.displayName) {
            ClaudeDesktop.forceQuit(profile)
            Log.write("quit \(profile.name): forced")
        }
    }

    // MARK: - Managing accounts

    /// One question (the name), then straight to signing in. Returns the new
    /// account's name, or nil if nothing was added.
    @discardableResult
    static func addAccount() async -> String? {
        guard !store.isDemo else { return nil }
        let accounts = accounts
        guard let typed = Dialogs.askNewAccountName(taken: { accounts.exists($0) }) else { return nil }
        // A new account starts the same as Default: shared history,
        // connectors and extensions. It can be switched off in Settings.
        guard await perform({
            let profile = try accounts.create(typed)
            try Sharing(store: accounts).setSameAsDefault(profile.name, true)
        }), let name = ProfileName.slug(typed), let profile = store.profile(named: name) else { return nil }
        await DesktopSignIn.run(profile)
        return name
    }

    /// Change the name shown for an account. Blank, or the original name
    /// typed back, removes the label.
    static func rename(_ profile: Profile, to typed: String) async {
        let original = profile.isDefault ? "Default" : profile.name
        let cleaned = AccountLabel.clean(typed)
        let label = cleaned == original ? nil : cleaned
        guard label != profile.label else { return }
        let accounts = accounts
        await perform { try accounts.setLabel(profile.name, to: label) }
    }

    static func setIcon(_ profile: Profile, to symbol: String?) async {
        let accounts = accounts
        await perform { try accounts.setIcon(profile.name, to: symbol) }
    }

    static func makeDockApp(_ profile: Profile) async {
        let accounts = accounts, cprof = bundledCprof, claude = ClaudeDesktop.appURL
        guard await perform({ try DockLauncher.make(profile.name, cprof: cprof, claudeApp: claude, store: accounts) })
        else { return }
        let app = accounts.paths.home.appendingPathComponent("Applications/Claude (\(profile.name)).app")
        NSWorkspace.shared.activateFileViewerSelecting([app])
        Dialogs.info("Drag “Claude (\(profile.name))” to your Dock")
    }

    static func reveal(_ profile: Profile) {
        guard !store.isDemo else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: profile.cliDir)])
    }

    /// Returns true if the account was removed.
    @discardableResult
    static func remove(_ profile: Profile) async -> Bool {
        guard !store.isDemo else { return false }
        let sharers = Sharing(store: accounts).historySharers(of: profile.name)
        if !sharers.isEmpty {
            let names = sharers.map { store.profile(named: $0)?.displayName ?? $0 }.joined(separator: ", ")
            Dialogs.info("“\(profile.displayName)” holds shared history",
                         "\(names) keep their Claude Code sessions in it. Stop sharing their history first.")
            return false
        }
        guard Dialogs.confirmRemove(profile.displayName) else { return false }
        guard await ClaudeDesktop.quit(profile) else {
            Dialogs.error("Quit Claude for “\(profile.displayName)” first.")
            return false
        }
        let accounts = accounts
        // Signing out removes the Keychain entry; it can take a moment.
        let signedOut = await Task.detached {
            !profile.codeSignedIn || ClaudeCode.signOut(configDir: accounts.cliDir(profile.name))
        }.value
        let name = profile.name
        guard await perform({ try accounts.remove(name); try Sharing(store: accounts).forget(name) }) else { return false }
        // Say something only if a step did not work.
        if !signedOut {
            Dialogs.info("Removed, but still signed in to Claude Code",
                         "To finish, delete the newest “Claude Code-credentials” entry in Keychain Access.")
        }
        return true
    }

    // MARK: - Sharing

    /// Make `profile` share `thing` with `source`, or stop (nil). Returns
    /// true if it changed.
    @discardableResult
    static func setSharing(_ thing: SharedThing, for profile: Profile, from source: Profile?) async -> Bool {
        // History is the one that moves files, so it is the one that asks.
        if thing == .history, let source,
           !Dialogs.confirm("Share Claude Code history between “\(profile.displayName)” and “\(source.displayName)”?",
                            "Their sessions go into one folder, so either can resume them.", button: "Share") {
            return false
        }
        let accounts = accounts, target = profile.name, from = source?.name
        let notes = Box<[String]>([])
        guard await perform({ notes.value = try Sharing(store: accounts).setSource(thing, for: target, to: from) })
        else { return false }
        Log.write("sharing: \(target) \(thing.rawValue) \(from.map { "from \($0)" } ?? "off")")
        if !notes.value.isEmpty { Dialogs.info("Some history was kept aside", notes.value.joined(separator: "\n")) }
        return true
    }

    /// Switch "Same as Default" for an account. Returns true if it changed.
    @discardableResult
    static func setSameAsDefault(_ profile: Profile, _ on: Bool) async -> Bool {
        let accounts = accounts, name = profile.name
        let main = store.profile(named: Profile.defaultName)?.displayName ?? "Default"
        if on, !Dialogs.confirm("Make “\(profile.displayName)” the same as \(main)?",
                                "Its Claude Code sessions join \(main)'s, and \(main)'s connectors and extensions are copied in.",
                                button: "Make Same") {
            return false
        }
        if !on, Sharing(store: accounts).source(.history, for: name) != nil,
           !Dialogs.confirm("Keep “\(profile.displayName)” separate?",
                            "It starts with an empty Claude Code history. The sessions it shared stay where they are.",
                            button: "Keep Separate") {
            return false
        }
        guard await perform({ try Sharing(store: accounts).setSameAsDefault(name, on) }) else { return false }
        Log.write("sharing: \(name) same as default \(on ? "on" : "off")")
        return true
    }

    // MARK: - The app itself

    /// The cprof program shipped inside this app.
    static var bundledCprof: URL {
        (Bundle.main.executableURL ?? Bundle.main.bundleURL).deletingLastPathComponent().appendingPathComponent("cprof")
    }

    private static var cprofLinks: [URL] {
        [URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin/cprof"),
         URL(fileURLWithPath: "/opt/homebrew/bin/cprof"), URL(fileURLWithPath: "/usr/local/bin/cprof")]
    }

    /// True when a `cprof` on the usual PATH folders points at this app's copy.
    static var commandLineToolInstalled: Bool {
        let mine = bundledCprof.resolvingSymlinksInPath().path
        return cprofLinks.contains { $0.resolvingSymlinksInPath().path == mine }
    }

    static func installCommandLineTool() async {
        let link = cprofLinks[0], target = bundledCprof
        await perform {
            let fm = FileManager.default
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: link)
            try fm.createSymbolicLink(at: link, withDestinationURL: target)
        }
    }

    static var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    static func setOpensAtLogin(_ on: Bool) {
        guard !store.isDemo else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Dialogs.error("Move Switchboard to your Applications folder, then try again.")
        }
    }

    /// Demo mode sets this, because a bare program has no version.
    static var versionOverride: String?

    static var version: String {
        versionOverride ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "development build"
    }

    static func openGuide() {
        if let url = Dialogs.guideURL { NSWorkspace.shared.open(url) }
    }

    static func showLog() {
        Log.write("log opened")
        NSWorkspace.shared.open(Log.fileURL)
    }
}

/// Carries a value out of work done on another thread.
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
