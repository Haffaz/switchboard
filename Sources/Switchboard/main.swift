import AppKit
import SwitchboardCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MenuController()
        self.controller = controller
        HotKeys.shared.onPress = { [weak controller] index in controller?.activateAccount(at: index) }
        HotKeys.shared.apply()
        Task {
            // If an earlier run stopped mid sign-in, hand claude:// links back.
            await LinkRelay.returnLinks()
            await ProfileStore.shared.refresh()
            if CommandLine.arguments.contains("--relay-selftest") { await relaySelfTest() }
        }
    }

    /// `Switchboard --relay-selftest`: hold the claude:// links for 12
    /// seconds, as during a sign-in, then give them back and quit. Used to
    /// check that links claimed by another app in that time are taken back.
    /// The outcome is in the log. No account is touched.
    private func relaySelfTest() async {
        Log.write("selftest: start")
        do { try await LinkRelay.shared.start(for: "selftest") } catch {
            Log.write("selftest: could not take the links: \(error.localizedDescription)")
        }
        try? await Task.sleep(for: .seconds(12))
        await LinkRelay.shared.stop()
        Log.write("selftest: end")
        NSApp.terminate(nil)
    }

    /// claude:// links arrive here only while Switchboard is relaying a sign-in.
    func application(_ application: NSApplication, open urls: [URL]) {
        LinkRelay.shared.handle(urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard LinkRelay.shared.signingIn != nil else { return .terminateNow }
        Task {
            await LinkRelay.shared.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

MainActor.assumeIsolated {
    // `Switchboard --demo-screenshots <folder>` shows sample accounts,
    // captures the menu and dialogs for the docs, and exits. It reads and
    // changes no real account.
    if let flag = CommandLine.arguments.firstIndex(of: "--demo-screenshots"),
       CommandLine.arguments.count > flag + 1 {
        Demo.run(output: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
    app.run()
}
