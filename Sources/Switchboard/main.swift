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
