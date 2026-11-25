import AppKit
import ServiceManagement
import SwitchboardCore

/// The menu bar menu, built only from standard macOS menu items. It draws
/// at once from the last known accounts, then refreshes in the background.
///
///   ● [icon] Default            ▸   one row per account; ● = Desktop running.
///     [icon] work               ▸   Its side menu holds every action for it.
///     [icon] side      Sign In  ▸   Clicking a row opens its Claude Desktop.
///   ───
///   Add Account…           ⌘N
///   Quit All Claude Desktops        (only while two or more are running)
///   ───
///   Open at Login
///   Install Command Line Tool       (only until it is installed)
///   Help
///   Quit Switchboard       ⌘Q
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let store = ProfileStore.shared

    override init() {
        super.init()
        statusItem.button?.image = MenuItems.barIcon()
        statusItem.button?.toolTip = "Switchboard: Claude accounts"
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        build()
        Task { if await store.refresh() { build() } }
    }

    private func build() {
        menu.removeAllItems()
        let profiles = store.profiles
        if profiles.isEmpty {
            menu.addItem(MenuItems.disabled("Loading…"))
        }
        let running = Set(profiles.filter { ClaudeDesktop.running($0) != nil }.map(\.name))
        for (index, profile) in profiles.enumerated() {
            menu.addItem(accountRow(profile, running: running.contains(profile.name),
                                    key: index < 9 ? "\(index + 1)" : ""))
        }

        menu.addItem(.separator())
        menu.addItem(item("Add Account…", #selector(addAccount), key: "n"))
        if running.count > 1 { menu.addItem(item("Quit All Claude Desktops", #selector(quitAllClaude))) }

        menu.addItem(.separator())
        let login = item("Open at Login", #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        if !Self.commandLineToolInstalled {
            menu.addItem(item("Install Command Line Tool", #selector(installCLI)))
        }
        menu.addItem(item("Help", #selector(showHelp)))
        menu.addItem(item("Quit Switchboard", #selector(quit), key: "q"))
    }

    /// The cprof program shipped inside this app.
    private static var bundledCprof: URL {
        (Bundle.main.executableURL ?? Bundle.main.bundleURL).deletingLastPathComponent().appendingPathComponent("cprof")
    }

    private static var cprofLink: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/bin/cprof")
    }

    /// True when ~/.local/bin/cprof points at this app's copy.
    private static var commandLineToolInstalled: Bool {
        cprofLink.resolvingSymlinksInPath().path == bundledCprof.resolvingSymlinksInPath().path
    }

    // MARK: - Accounts

    /// One account: its icon and name, a green dot while its Claude Desktop
    /// runs, and a "Sign In" badge until Desktop is signed in.
    private func accountRow(_ profile: Profile, running: Bool, key: String) -> NSMenuItem {
        let row = item(profile.displayName, #selector(openDesktop(_:)), profile)
        row.image = MenuItems.symbol(profile.iconSymbol) ?? MenuItems.symbol(AccountIcon.fallback)
        row.onStateImage = MenuItems.runningDot()
        row.state = running ? .on : .off
        if profile.needsDesktopSignIn { row.badge = NSMenuItemBadge(string: "Sign In") }
        row.toolTip = running ? "Claude Desktop is running" : nil
        row.submenu = accountMenu(profile, running: running, key: key)
        return row
    }

    private func accountMenu(_ profile: Profile, running: Bool, key: String) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        sub.addItem(MenuItems.disabled(profile.codeSignedIn ? profile.email : "Claude Code not signed in"))
        sub.addItem(.separator())

        sub.addItem(item(profile.needsDesktopSignIn ? "Sign In to Claude Desktop…" : "Open Claude Desktop",
                         #selector(openDesktop(_:)), profile, key: key))
        let code = item(profile.codeSignedIn ? "Open Claude Code" : "Sign In to Claude Code…",
                        #selector(openCode(_:)), profile, key: key)
        code.keyEquivalentModifierMask = [.command, .shift]
        sub.addItem(code)
        sub.addItem(item("Open Terminal", #selector(openTerminal(_:)), profile))

        if running {
            sub.addItem(.separator())
            sub.addItem(item("Quit Claude Desktop", #selector(quitClaude(_:)), profile))
        }

        sub.addItem(.separator())
        let icon = NSMenuItem(title: "Icon", action: nil, keyEquivalent: "")
        icon.submenu = iconMenu(profile)
        sub.addItem(icon)
        if !profile.isDefault && profile.desktopSignedIn {
            sub.addItem(item("Sign In to Claude Desktop Again…", #selector(signInDesktop(_:)), profile))
        }
        if profile.codeSignedIn {
            sub.addItem(item("Sign In to Claude Code Again…", #selector(signInCode(_:)), profile))
        }
        if !profile.isDefault { sub.addItem(item("Add Dock Icon", #selector(makeDockApp(_:)), profile)) }
        sub.addItem(item("Show Files in Finder", #selector(reveal(_:)), profile))

        if !profile.isDefault {
            sub.addItem(.separator())
            sub.addItem(item("Remove Account…", #selector(remove(_:)), profile))
        }
        return sub
    }

    private func iconMenu(_ profile: Profile) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        for choice in AccountIcon.choices {
            let entry = item(choice.label, #selector(setIcon(_:)), profile)
            entry.image = MenuItems.symbol(choice.symbol)
            entry.identifier = NSUserInterfaceItemIdentifier(choice.symbol)
            entry.state = profile.icon == choice.symbol ? .on : .off
            sub.addItem(entry)
        }
        sub.addItem(.separator())
        let none = item("None", #selector(setIcon(_:)), profile)
        none.identifier = NSUserInterfaceItemIdentifier("")
        none.state = (profile.icon ?? "").isEmpty ? .on : .off
        sub.addItem(none)
        return sub
    }

    private func item(_ title: String, _ selector: Selector, _ profile: Profile? = nil,
                      key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        item.representedObject = profile?.name
        return item
    }

    // MARK: - Actions

    /// The account a menu item stands for, as currently known.
    private func profile(_ sender: NSMenuItem) -> Profile? {
        (sender.representedObject as? String).flatMap(store.profile(named:))
    }

    private let accounts = AccountStore()

    /// Do some work on the accounts; show any error in plain words, then
    /// reload the menu's copy. Returns false if it failed.
    @discardableResult
    private func perform(_ work: @Sendable @escaping () throws -> Void) async -> Bool {
        do {
            try await Task.detached(operation: work).value
            await store.refresh(recheckLogins: true)
            return true
        } catch {
            Dialogs.error(error.localizedDescription.prefix(1).uppercased() + error.localizedDescription.dropFirst())
            return false
        }
    }

    @objc private func openDesktop(_ sender: NSMenuItem) {
        guard let profile = profile(sender) else { return }
        Task {
            if profile.needsDesktopSignIn { await DesktopSignIn.run(profile); return }
            do { try await ClaudeDesktop.open(profile) } catch { Dialogs.error(error.localizedDescription) }
        }
    }

    @objc private func openCode(_ sender: NSMenuItem) {
        guard let profile = profile(sender) else { return }
        openTerminal(profile, profile.codeSignedIn ? .claudeCode : .signIn)
    }

    private func openTerminal(_ profile: Profile, _ mode: TerminalLauncher.Mode) {
        let accounts = accounts
        Task { await perform { try TerminalLauncher.open(profile.name, mode: mode, store: accounts) } }
    }

    @objc private func setIcon(_ sender: NSMenuItem) {
        guard let profile = profile(sender), let symbol = sender.identifier?.rawValue else { return }
        let accounts = accounts
        Task { await perform { try accounts.setIcon(profile.name, to: symbol) } }
    }

    @objc private func signInDesktop(_ sender: NSMenuItem) {
        guard let profile = profile(sender) else { return }
        Task { await DesktopSignIn.run(profile) }
    }

    @objc private func quitClaude(_ sender: NSMenuItem) {
        guard let profile = profile(sender) else { return }
        Task { await quit(profile) }
    }

    @objc private func quitAllClaude() {
        let running = store.profiles.filter { ClaudeDesktop.running($0) != nil }
        Task { for profile in running { await quit(profile) } }
    }

    private func quit(_ profile: Profile) async {
        Log.write("quit \(profile.name): asked")
        if await ClaudeDesktop.quit(profile) { return }
        // Claude can refuse to quit while work is running.
        if Dialogs.confirm("Claude (\(profile.displayName)) is still running",
                           "It may be finishing work, or waiting for you in its own window. "
                           + "Force quit it? Anything unsaved in that window is lost.", button: "Force Quit") {
            ClaudeDesktop.forceQuit(profile)
            Log.write("quit \(profile.name): forced")
        }
    }

    @objc private func openTerminal(_ sender: NSMenuItem) {
        if let profile = profile(sender) { openTerminal(profile, .shell) }
    }

    @objc private func signInCode(_ sender: NSMenuItem) {
        if let profile = profile(sender) { openTerminal(profile, .signIn) }
    }

    @objc private func makeDockApp(_ sender: NSMenuItem) {
        guard let profile = profile(sender) else { return }
        let accounts = accounts, cprof = Self.bundledCprof, claude = ClaudeDesktop.appURL
        Task {
            guard await perform({ try DockLauncher.make(profile.name, cprof: cprof, claudeApp: claude, store: accounts) })
            else { return }
            let app = accounts.paths.home.appendingPathComponent("Applications/Claude (\(profile.name)).app")
            NSWorkspace.shared.activateFileViewerSelecting([app])
            Dialogs.info("Dock icon ready", "Drag “Claude (\(profile.name))” from the Finder window to your Dock.")
        }
    }

    @objc private func reveal(_ sender: NSMenuItem) {
        guard let profile = profile(sender) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: profile.cliDir)])
    }

    @objc private func remove(_ sender: NSMenuItem) {
        guard let profile = profile(sender), Dialogs.confirmRemove(profile.name) else { return }
        Task {
            guard await ClaudeDesktop.quit(profile) else {
                Dialogs.error("Claude for “\(profile.name)” is still running. Quit it, then remove the account.")
                return
            }
            let accounts = accounts
            // Signing out removes the Keychain entry; it can take a moment.
            let signedOut = await Task.detached {
                !profile.codeSignedIn || ClaudeCode.signOut(configDir: accounts.cliDir(profile.name))
            }.value
            guard await perform({ try accounts.remove(profile.name) }) else { return }
            Dialogs.info("Removed “\(profile.name)”", signedOut
                ? "Its sign-in, history and settings are gone from this Mac."
                : "Its history and settings are gone. Its Claude Code sign-in could not be removed from Keychain; "
                  + "open Keychain Access and delete the newest “Claude Code-credentials” entry if you want it gone.")
        }
    }

    @objc private func addAccount() {
        guard let name = Dialogs.askNewAccountName() else { return }
        Task {
            let accounts = accounts
            guard await perform({ try accounts.add(name) }), let profile = store.profile(named: name) else { return }
            let next = Dialogs.afterCreate(name)
            if next == .code || next == .both { openTerminal(profile, .signIn) }
            if next == .desktop || next == .both { await DesktopSignIn.run(profile) }
        }
    }

    @objc private func installCLI() {
        let link = Self.cprofLink, target = Self.bundledCprof
        Task {
            let done = await perform {
                let fm = FileManager.default
                try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: link)
                try fm.createSymbolicLink(at: link, withDestinationURL: target)
            }
            guard done else { return }
            Dialogs.info("Command line tool installed", """
                You can now run `cprof` in a terminal (it is in ~/.local/bin).

                Optional: to make `claude` follow each folder's account, add this line to ~/.zshrc:
                eval "$(cprof init zsh)"
                """)
        }
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            Dialogs.error("Could not change Open at Login. Move the app to your Applications folder and try again.\n\n\(error.localizedDescription)")
        }
    }

    @objc private func showHelp() {
        guard Dialogs.help() == .showLog else { return }
        Log.write("log opened")
        NSWorkspace.shared.open(Log.fileURL)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
