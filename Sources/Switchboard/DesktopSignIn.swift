import AppKit
import SwitchboardCore

/// Signs one account's Claude Desktop in, with every other Claude left open.
@MainActor
enum DesktopSignIn {
    private static let confirmSeconds = 20

    static func run(_ profile: Profile) async {
        if let busy = LinkRelay.shared.signingIn, busy != profile.name {
            let busyName = ProfileStore.shared.profile(named: busy)?.displayName ?? busy
            Dialogs.info("Finish signing in to “\(busyName)” first")
            return
        }

        Log.write("sign-in \(profile.name): start")
        let app: NSRunningApplication
        do { app = try await ClaudeDesktop.open(profile) } catch {
            Log.write("sign-in \(profile.name): could not open Claude: \(error.localizedDescription)")
            Dialogs.error(error.localizedDescription)
            return
        }
        // A starting Claude claims claude:// for itself. Let it finish, so
        // that Switchboard takes the links after it, not before.
        await waitUntilLaunched(app)

        do { try await LinkRelay.shared.start(for: profile.name) } catch {
            Log.write("sign-in \(profile.name): could not take over links: \(error.localizedDescription)")
            Dialogs.error(error.localizedDescription)
            return
        }
        let name = profile.name
        LinkRelay.shared.onSignInDelivered = { name in
            LinkRelay.shared.onSignInDelivered = nil  // once, even if the browser repeats the link
            Task { await complete(name, waitForProof: true) }
        }
        // Claude usually finishes in its own sign-in sheet, with no link for
        // Switchboard to pass on. Notice that by watching for the sign-in.
        if !profile.desktopSignedIn {
            Task { await watchForSignIn(name) }
        }

        // If this is refused, the relay holds the link and offers Try Again.
        let allowed = await LinkRelay.requestAutomationPermission(pid: app.processIdentifier)
        Log.write("sign-in \(profile.name): automation permission \(allowed ? "granted" : "not granted yet")")
    }

    private static func waitUntilLaunched(_ app: NSRunningApplication) async {
        for _ in 0..<60 where !app.isFinishedLaunching && !app.isTerminated {
            try? await Task.sleep(for: .milliseconds(250))
        }
        try? await Task.sleep(for: .milliseconds(750))
    }

    private static func isSignedIn(_ name: String) async -> Bool {
        await ProfileStore.shared.refresh()
        return ProfileStore.shared.profile(named: name)?.desktopSignedIn ?? false
    }

    /// While this account's sign-in is in progress, check every two seconds
    /// whether Claude has saved it.
    private static func watchForSignIn(_ name: String) async {
        while LinkRelay.shared.signingIn == name {
            try? await Task.sleep(for: .seconds(2))
            guard LinkRelay.shared.signingIn == name else { return }
            if await isSignedIn(name) {
                await complete(name, waitForProof: false)
                return
            }
        }
    }

    /// End the sign-in and tell the person how it went. Safe to reach twice
    /// (a passed-on link and the watcher can both notice): the second is ignored.
    private static func complete(_ name: String, waitForProof: Bool) async {
        guard LinkRelay.shared.signingIn == name, !finishing.contains(name) else { return }
        finishing.insert(name)
        defer { finishing.remove(name) }

        var confirmed = await isSignedIn(name)
        if waitForProof {
            for _ in 0..<confirmSeconds where !confirmed {
                try? await Task.sleep(for: .seconds(1))
                confirmed = await isSignedIn(name)
            }
        }
        await LinkRelay.shared.stop()
        Log.write("sign-in \(name): \(confirmed ? "done" : "sent, not confirmed")")
        // A finished sign-in needs no pop-up: the Claude window shows it.
        // Speak up only when it may not have worked.
        if !confirmed {
            let shown = ProfileStore.shared.profile(named: name)?.displayName ?? name
            Dialogs.info("Check the Claude window for “\(shown)”", "If it still asks you to sign in, try again.")
        }
    }

    private static var finishing: Set<String> = []
}
