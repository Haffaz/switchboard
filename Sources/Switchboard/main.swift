import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MenuController()
        Task {
            // If an earlier run stopped mid sign-in, hand claude:// links back.
            await LinkRelay.returnLinks()
            await ProfileStore.shared.refresh()
        }
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
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
    app.run()
}
