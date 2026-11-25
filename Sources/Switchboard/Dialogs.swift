import AppKit
import SwitchboardCore

/// Every pop-up window, in one place. Each says one thing, in as few words
/// as it takes. Details belong in the guides, not here.
@MainActor
enum Dialogs {
    /// Demo mode sets this, because a bare program has no app icon.
    static var iconOverride: NSImage?

    static let guideURL = URL(string: "https://github.com/Haffaz/switchboard#documentation")

    private static func makeAlert(_ title: String, _ text: String = "", style: NSAlert.Style = .informational) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        if let iconOverride { alert.icon = iconOverride }
        return alert
    }

    private static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    private static func nameField(_ value: String, placeholder: String, in alert: NSAlert) -> NSTextField {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = value
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return field
    }

    // MARK: - Accounts

    /// Ask what to call a new account. Returns the name as typed, or nil if
    /// cancelled. `taken` says whether a name is already in use.
    static func askNewAccountName(taken: (String) -> Bool) -> String? {
        let alert = makeAlert("New Account")
        let field = nameField("", placeholder: "Name, like Work", in: alert)
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        while run(alert) == .alertFirstButtonReturn {
            guard let typed = AccountLabel.clean(field.stringValue), let slug = ProfileName.slug(typed) else {
                alert.informativeText = "Use at least one letter or number."
                continue
            }
            if slug == Profile.defaultName || taken(slug) {
                alert.informativeText = "That name is taken."
                continue
            }
            return typed
        }
        return nil
    }

    /// Ask for a new shown name. Nil means cancelled; an empty string means
    /// "go back to the original name".
    static func askRename(current: String, original: String) -> String? {
        let alert = makeAlert("Rename")
        let field = nameField(current, placeholder: original, in: alert)
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        guard run(alert) == .alertFirstButtonReturn else { return nil }
        return AccountLabel.clean(field.stringValue) ?? ""
    }

    static func confirmRemove(_ name: String) -> Bool {
        let alert = makeAlert("Remove “\(name)”?", "Its chats and settings on this Mac will be deleted.", style: .warning)
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        return run(alert) == .alertFirstButtonReturn
    }

    static func confirmForceQuit(_ name: String) -> Bool {
        let alert = makeAlert("Claude (\(name)) is still running",
                              "Force quit it? Unsaved work in that window is lost.", style: .warning)
        alert.addButton(withTitle: "Force Quit")
        alert.addButton(withTitle: "Cancel")
        return run(alert) == .alertFirstButtonReturn
    }

    // MARK: - Sign-in

    enum DeliveryChoice { case retry, openSettings, cancel }

    static func deliveryFailed(_ name: String) -> DeliveryChoice {
        let alert = makeAlert("Allow Switchboard to control Claude",
                              "System Settings → Privacy & Security → Automation.", style: .warning)
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Cancel")
        switch run(alert) {
        case .alertFirstButtonReturn: return .openSettings
        case .alertSecondButtonReturn: return .retry
        default: return .cancel
        }
    }

    /// One plain question with a single action and Cancel.
    static func confirm(_ title: String, _ text: String = "", button: String) -> Bool {
        let alert = makeAlert(title, text)
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return run(alert) == .alertFirstButtonReturn
    }

    // MARK: - Messages

    static func info(_ title: String, _ text: String = "") {
        _ = run(makeAlert(title, text))
    }

    static func error(_ text: String) {
        _ = run(makeAlert("Something went wrong", text, style: .warning))
    }

    enum HelpChoice { case done, guide, showLog }

    static func help() -> HelpChoice {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let alert = makeAlert(version.map { "Switchboard \($0)" } ?? "Switchboard", """
            Click an account to open its Claude Desktop.
            Point at it for Claude Code and more.
            A green dot means it is running.

            Not affiliated with Anthropic.
            """)
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Open Guide")
        alert.addButton(withTitle: "Show Log")
        switch run(alert) {
        case .alertSecondButtonReturn: return .guide
        case .alertThirdButtonReturn: return .showLog
        default: return .done
        }
    }
}
