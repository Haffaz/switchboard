import AppKit
import SwitchboardCore

/// The menu bar menu: only what is used many times a day. Everything rare,
/// or that needs explaining (adding an account too), lives in Settings.
///
///   ● [icon] Work               ▸   [icon] Open Claude Desktop    ⌘1
///   ● [icon] Personal     (2)   ▸   [icon] Open Claude Code      ⇧⌘1
///     [icon] Side      Sign In  ▸   ───                       (while running:)
///   ───                             [icon] Restart to Show 2 New Sessions
///     [icon] Settings…     ⌘,       [icon] Quit Claude Desktop
///     [icon] Quit Switchboard ⌘Q    ───
///                                   [icon] Account Settings…
///
/// (2) counts shared Code tab sessions that a running Claude Desktop only
/// shows after a restart.
///
/// Every row has an icon. macOS 26 adds one by itself to rows it knows,
/// such as Settings, so giving each row its own keeps the column even.
///
/// It draws at once from the last known accounts, then refreshes in the
/// background and redraws if anything changed.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let store = ProfileStore.shared
    /// For demo mode: waiting sessions per account, instead of reading disk.
    var pendingOverride: [String: Int]?

    override init() {
        super.init()
        statusItem.button?.image = MenuItems.barIcon()
        statusItem.button?.toolTip = "Switchboard \(Actions.version)"
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    /// For demo mode: the menu, freshly built, and one account's side menu.
    func builtMenu() -> NSMenu { build(); return menu }
    func builtAccountMenu(_ name: String) -> NSMenu? {
        build()
        return menu.items.first { ($0.representedObject as? String) == name }?.submenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        build()
        Task { if await store.refresh() { build() } }
    }

    private func build() {
        menu.removeAllItems()
        let profiles = store.profiles
        if profiles.isEmpty { menu.addItem(MenuItems.disabled("Loading…")) }
        let running = store.runningNames()
        for (index, profile) in profiles.enumerated() {
            let isRunning = running.contains(profile.name)
            menu.addItem(accountRow(profile, running: isRunning, waiting: isRunning ? waiting(profile) : 0,
                                    key: index < 9 ? "\(index + 1)" : ""))
        }
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ",", icon: "gearshape"))
        menu.addItem(item("Quit Switchboard", #selector(quit), key: "q", icon: "power"))
    }

    /// Shared Code tab sessions a running Claude Desktop will show after a restart.
    private func waiting(_ profile: Profile) -> Int {
        if let pendingOverride { return pendingOverride[profile.name] ?? 0 }
        return Sharing(store: Actions.accounts).pendingCodeSessions(profile.name)
    }

    /// One account: its icon and name, a green dot while its Claude Desktop
    /// runs, a "Sign In" badge until Desktop is signed in, and otherwise a
    /// count of shared sessions waiting for a restart.
    private func accountRow(_ profile: Profile, running: Bool, waiting: Int, key: String) -> NSMenuItem {
        let row = item(profile.displayName, #selector(openDesktop(_:)), profile)
        row.image = MenuItems.symbol(profile.iconSymbol) ?? MenuItems.symbol(AccountIcon.fallback)
        row.onStateImage = MenuItems.runningDot()
        row.state = running ? .on : .off
        if profile.needsDesktopSignIn {
            row.badge = NSMenuItemBadge(string: "Sign In")
        } else if waiting > 0 {
            row.badge = NSMenuItemBadge(count: waiting)
        }
        row.toolTip = [profile.isDefault ? "Main account" : nil,
                       running ? "Claude Desktop is running" : nil,
                       waiting > 0 ? "\(Self.sessions(waiting)) to show after a restart" : nil]
            .compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        row.submenu = accountMenu(profile, running: running, waiting: waiting, key: key)
        return row
    }

    private static func sessions(_ count: Int) -> String {
        count == 1 ? "1 new shared session" : "\(count) new shared sessions"
    }

    private func accountMenu(_ profile: Profile, running: Bool, waiting: Int, key: String) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        sub.addItem(item(profile.needsDesktopSignIn ? "Sign In to Claude Desktop…" : "Open Claude Desktop",
                         #selector(openDesktop(_:)), profile, key: key, icon: "macwindow"))
        let code = item(profile.codeSignedIn ? "Open Claude Code" : "Sign In to Claude Code…",
                        #selector(openCode(_:)), profile, key: key, icon: "chevron.left.forwardslash.chevron.right")
        code.keyEquivalentModifierMask = [.command, .shift]
        sub.addItem(code)
        if running {
            sub.addItem(.separator())
            let restart = waiting > 0 ? "Restart to Show \(waiting == 1 ? "1 New Session" : "\(waiting) New Sessions")"
                                      : "Restart Claude Desktop"
            sub.addItem(item(restart, #selector(restartClaude(_:)), profile, icon: "arrow.clockwise"))
            sub.addItem(item("Quit Claude Desktop", #selector(quitClaude(_:)), profile, icon: "xmark.circle"))
        }
        sub.addItem(.separator())
        sub.addItem(item("Account Settings…", #selector(openAccountSettings(_:)), profile, icon: "slider.horizontal.3"))
        return sub
    }

    private func item(_ title: String, _ selector: Selector, _ profile: Profile? = nil,
                      key: String = "", icon: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.image = icon.flatMap { MenuItems.symbol($0) }
        item.target = self
        item.representedObject = profile?.name
        return item
    }

    // MARK: - Actions

    /// The account a menu item stands for, as currently known.
    private func profile(_ sender: NSMenuItem) -> Profile? {
        (sender.representedObject as? String).flatMap(store.profile(named:))
    }

    @objc private func openDesktop(_ sender: NSMenuItem) {
        if let profile = profile(sender) { Task { await Actions.openDesktop(profile) } }
    }

    @objc private func openCode(_ sender: NSMenuItem) {
        if let profile = profile(sender) { Task { await Actions.openCode(profile) } }
    }

    @objc private func restartClaude(_ sender: NSMenuItem) {
        if let profile = profile(sender) { Task { await Actions.restartDesktop(profile) } }
    }

    @objc private func openAccountSettings(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        SettingsWindow.shared.model.selected = name
        SettingsWindow.shared.show(.accounts)
    }

    @objc private func quitClaude(_ sender: NSMenuItem) {
        if let profile = profile(sender) { Task { await Actions.quit(profile) } }
    }

    @objc private func openSettings() { SettingsWindow.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
