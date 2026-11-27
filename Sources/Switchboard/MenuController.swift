import AppKit
import SwitchboardCore

/// The menu bar menu: only what is used many times a day. Everything rare,
/// or that needs explaining, lives in the Settings window.
///
///   ● [icon] Work               ▸   Open Claude Desktop      ⌘1
///     [icon] Personal           ▸   Open Claude Code        ⇧⌘1
///     [icon] Side      Sign In  ▸   Open Terminal
///   ───                             Quit Claude Desktop      (while running)
///   Add Account…           ⌘N
///   Settings…              ⌘,
///   Quit Switchboard       ⌘Q
///
/// It draws at once from the last known accounts, then refreshes in the
/// background and redraws if anything changed.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let store = ProfileStore.shared

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
            menu.addItem(accountRow(profile, running: running.contains(profile.name),
                                    key: index < 9 ? "\(index + 1)" : ""))
        }
        menu.addItem(.separator())
        menu.addItem(item("Add Account…", #selector(addAccount), key: "n"))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit Switchboard", #selector(quit), key: "q"))
    }

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

    @objc private func openDesktop(_ sender: NSMenuItem) {
        if let profile = profile(sender) { Task { await Actions.openDesktop(profile) } }
    }

    @objc private func openCode(_ sender: NSMenuItem) {
        if let profile = profile(sender) { Task { await Actions.openCode(profile) } }
    }

    @objc private func openTerminal(_ sender: NSMenuItem) {
        if let profile = profile(sender) { Task { await Actions.openTerminal(profile, .shell) } }
    }

    @objc private func quitClaude(_ sender: NSMenuItem) {
        if let profile = profile(sender) { Task { await Actions.quit(profile) } }
    }

    @objc private func addAccount() { Task { await Actions.addAccount() } }
    @objc private func openSettings() { SettingsWindow.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
