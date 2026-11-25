import AppKit
import SwitchboardCore

/// All pop-up windows in one place, worded for people, not terminals.
@MainActor
enum Dialogs {
    /// Demo mode sets this, because a bare program has no app icon.
    static var iconOverride: NSImage?

    private static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        if let iconOverride { alert.icon = iconOverride }
        return alert
    }

    enum NextStep { case both, desktop, code, later }

    static func askNewAccountName() -> String? {
        let alert = makeAlert()
        alert.messageText = "Add a Claude account"
        alert.informativeText = "Give it a short name you’ll recognise, like “Work” or “Personal”. "
            + "You’ll sign in on the next step."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Work"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)

        while alert.runModal() == .alertFirstButtonReturn {
            guard let slug = ProfileName.slug(field.stringValue) else {
                alert.informativeText = "Please type a name using letters or numbers."
                continue
            }
            if slug == "default" {
                alert.informativeText = "“Default” is your usual setup. Please pick another name."
                continue
            }
            return slug
        }
        return nil
    }

    static func afterCreate(_ name: String) -> NextStep {
        let alert = makeAlert()
        alert.messageText = "“\(name)” is ready. Sign in now?"
        alert.informativeText = "Claude Desktop and Claude Code each have their own sign-in. "
            + "Sign in to the same account in both, or only the one you use."
        alert.addButton(withTitle: "Sign In to Both")
        alert.addButton(withTitle: "Only Claude Desktop")
        alert.addButton(withTitle: "Only Claude Code")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .both
        case .alertSecondButtonReturn: return .desktop
        case .alertThirdButtonReturn: return .code
        default: return .later
        }
    }

    static func confirmRemove(_ name: String) -> Bool {
        let alert = makeAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove “\(name)”?"
        alert.informativeText = "This signs “\(name)” out of Claude Code and deletes its chat history "
            + "and settings on this Mac. Your Claude account itself is not affected. "
            + "Quit its Claude Desktop window first."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Explains the Claude Desktop sign-in before it starts.
    static func signInIntro(_ name: String) -> Bool {
        confirm("Sign in to Claude Desktop as “\(name)”", """
            After you click Continue:
            1. Sign in in the Claude window that opens (Google or email).
            2. When your browser asks, click “Open Claude”.

            Switchboard sends you back to the right window. Your other Claude windows stay open.
            """, button: "Continue")
    }

    static func confirm(_ title: String, _ text: String, button: String) -> Bool {
        let alert = makeAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    enum DeliveryChoice { case retry, openSettings, cancel }

    static func deliveryFailed(_ profile: String) -> DeliveryChoice {
        let alert = makeAlert()
        alert.alertStyle = .warning
        alert.messageText = "Almost there: allow Switchboard to talk to Claude"
        alert.informativeText = "Switchboard caught the sign-in for “\(profile)” but macOS blocked passing it on. "
            + "Allow Switchboard to control Claude in System Settings → Privacy & Security → Automation."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .openSettings
        case .alertSecondButtonReturn: return .retry
        default: return .cancel
        }
    }

    static func info(_ title: String, _ text: String) {
        show(title, text, style: .informational)
    }

    static func error(_ text: String) {
        show("Something went wrong", text, style: .warning)
    }

    enum HelpChoice { case done, showLog }

    static func help() -> HelpChoice {
        let alert = makeAlert()
        alert.messageText = "Switchboard"
        alert.informativeText = """
            Each account has its own Claude Desktop and its own Claude Code sign-in.

            • Point at an account to see its actions. Clicking the account opens its Claude Desktop.
            • A green dot means that account’s Claude Desktop is running. Closing its window leaves it running; choose Quit Claude Desktop to stop it.
            • ⌘1, ⌘2… open Claude Desktop and ⇧⌘1, ⇧⌘2… open Claude Code while the menu is open.
            • “Default” is the setup you had before. It is never changed.
            • Your CLAUDE.md, rules, agents, skills and settings are shared by every account. Chat history, sign-in and MCP servers stay separate.

            Switchboard is an independent tool, not made by Anthropic.
            """
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Show Log")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn ? .showLog : .done
    }

    private static func show(_ title: String, _ text: String, style: NSAlert.Style) {
        let alert = makeAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
