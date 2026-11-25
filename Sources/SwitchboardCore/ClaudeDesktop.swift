import AppKit

/// Everything about running Claude Desktop copies: finding the app, telling
/// the copies apart, opening, and quitting. All copies share one bundle ID,
/// so each is identified by the data folder in its launch arguments.
@MainActor
public enum ClaudeDesktop {
    public nonisolated static let bundleID = "com.anthropic.claudefordesktop"

    /// Where Claude Desktop is installed, wherever that is.
    public nonisolated static var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    public static func running(_ profile: Profile) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { app in
            guard !app.isTerminated, let args = ProcessArguments.of(pid: app.processIdentifier) else { return false }
            return ProcessArguments.belongs(args, to: profile)
        }
    }

    /// Open this account's Claude, or bring its existing window forward.
    /// Returns the copy that belongs to the account.
    @discardableResult
    public static func open(_ profile: Profile) async throws -> NSRunningApplication {
        if let existing = running(profile) {
            await bringForward(existing)
            return existing
        }
        guard let appURL else {
            throw SwitchboardError("Claude Desktop is not installed. Get it from claude.ai/download.")
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true  // never reuse another account's copy
        config.arguments = profile.desktopDir.isEmpty ? [] : [ProcessArguments.userDataDirFlag + profile.desktopDir]
        return try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    }

    /// Show a running copy without making it open another window. If it has
    /// no window on screen (closed or minimised), ask it to reopen one, the
    /// same request a Dock click sends.
    private static func bringForward(_ app: NSRunningApplication) async {
        app.unhide()
        app.activate(options: [.activateAllWindows])
        guard !hasWindowOnScreen(app.processIdentifier) else { return }
        let pid = app.processIdentifier
        let sent = await Task.detached { () -> Bool in
            let event = NSAppleEventDescriptor(
                eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
                targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            return (try? event.sendEvent(options: [.noReply], timeout: 5)) != nil
        }.value
        Log.write("show: asked pid \(pid) to reopen its window (\(sent ? "sent" : "not allowed"))")
    }

    /// True if the process has a normal window on screen. Needs no special
    /// permission: only window owners and layers are read, not contents.
    private static func hasWindowOnScreen(_ pid: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return true }
        return windows.contains { info in
            (info[kCGWindowOwnerPID as String] as? pid_t) == pid && (info[kCGWindowLayer as String] as? Int) == 0
        }
    }

    /// Ask one account's Claude to quit. Returns false if it is still
    /// running after the grace period (Claude can refuse while busy).
    public static func quit(_ profile: Profile, waitSeconds: Double = 8) async -> Bool {
        guard let app = running(profile) else { return true }
        app.terminate()
        let deadline = Date().addingTimeInterval(waitSeconds)
        while Date() < deadline {
            if app.isTerminated { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return app.isTerminated
    }

    public static func forceQuit(_ profile: Profile) {
        running(profile)?.forceTerminate()
    }
}
