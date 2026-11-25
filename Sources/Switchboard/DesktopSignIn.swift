import AppKit
import SwitchboardCore

/// Signs one account's Claude Desktop in, with every other Claude left open.
@MainActor
enum DesktopSignIn {
    private static let confirmSeconds = 20

    static func run(_ profile: Profile) async {
        if let busy = LinkRelay.shared.signingIn, busy != profile.name {
            let busyName = ProfileStore.shared.profile(named: busy)?.displayName ?? busy
            Dialogs.info("One sign-in at a time",
                         "“\(busyName)” is still signing in. Finish that first, then try “\(profile.displayName)”.")
            return
        }
        // Shown first: a dialog left open later would hold back the link.
        guard Dialogs.signInIntro(profile.displayName) else { return }

        Log.write("sign-in \(profile.name): start")
        let app: NSRunningApplication
        do { app = try await ClaudeDesktop.open(profile) } catch {
            Log.write("sign-in \(profile.name): could not open Claude: \(error.localizedDescription)")
            Dialogs.error(error.localizedDescription)
            return
        }

        // Catch the link first, so it cannot slip past while a prompt is open.
        do { try await LinkRelay.shared.start(for: profile.name) } catch {
            Log.write("sign-in \(profile.name): could not take over links: \(error.localizedDescription)")
            Dialogs.error("Switchboard could not take over sign-in links: \(error.localizedDescription)")
            return
        }
        LinkRelay.shared.onSignInDelivered = { name in
            LinkRelay.shared.onSignInDelivered = nil  // once, even if the browser repeats the link
            Task { await finish(name, wasSignedIn: profile.desktopSignedIn) }
        }

        // If this is refused, the relay holds the link and offers Try Again.
        let allowed = await LinkRelay.requestAutomationPermission(pid: app.processIdentifier)
        Log.write("sign-in \(profile.name): automation permission \(allowed ? "granted" : "not granted yet")")
    }

    /// Wait until Claude has really saved the sign-in before saying so.
    private static func finish(_ name: String, wasSignedIn: Bool) async {
        var confirmed = wasSignedIn
        for _ in 0..<confirmSeconds where !confirmed {
            try? await Task.sleep(for: .seconds(1))
            await ProfileStore.shared.refresh()
            confirmed = ProfileStore.shared.profile(named: name)?.desktopSignedIn ?? false
        }
        if wasSignedIn { try? await Task.sleep(for: .seconds(5)) }  // let repeat deliveries land
        await LinkRelay.shared.stop()
        Log.write("sign-in \(name): \(confirmed ? "done" : "sent, not confirmed")")
        let shown = ProfileStore.shared.profile(named: name)?.displayName ?? name
        if confirmed {
            Dialogs.info("“\(shown)” is signed in", "Claude Desktop for “\(shown)” is ready.")
        } else {
            Dialogs.info("Check the Claude window for “\(shown)”",
                         "Switchboard passed the sign-in on, but Claude has not confirmed it yet. "
                         + "If its window still shows the sign-in page, try again.")
        }
    }
}
