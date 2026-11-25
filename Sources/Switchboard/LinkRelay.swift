import AppKit
import SwitchboardCore

/// Routes `claude://` links to the right Claude Desktop copy during sign-in.
///
/// The browser finishes a sign-in by opening a `claude://` link, and macOS
/// hands that to whichever Claude copy it likes. So for the length of one
/// sign-in, Switchboard becomes the handler for `claude://`, passes the
/// sign-in link to the account that asked for it, passes every other link
/// to the default Claude, and then gives the links back.
///
/// Two facts about Claude Desktop shape this:
/// - Every Claude copy claims `claude://` for itself when it starts. So
///   Switchboard keeps watch and takes the links back for as long as the
///   sign-in lasts.
/// - When Claude sees it is not the `claude://` handler, it signs in through
///   its own sign-in sheet and needs no link at all. That is the usual path
///   here; passing a link on is the fallback.
@MainActor
final class LinkRelay {
    static let shared = LinkRelay()
    private static let previousHandlerKey = "previousClaudeLinkHandler"
    private static let timeout: Duration = .seconds(600)

    /// The one account signing in right now. Only one at a time: a second
    /// would make it impossible to know whose link arrived.
    private(set) var signingIn: String?
    private var expiry: Task<Void, Never>?
    private var watch: Task<Void, Never>?
    var onSignInDelivered: ((String) -> Void)?

    // MARK: - Owning the links

    func start(for profile: String) async throws {
        if let current = signingIn, current != profile {
            throw SwitchboardError("“\(current)” is still signing in. Finish or cancel that first.")
        }
        if let owner = Self.currentHandler(), !Self.same(owner, Bundle.main.bundleURL) {
            UserDefaults.standard.set(owner.path, forKey: Self.previousHandlerKey)
        }
        try await Self.takeLinks()
        signingIn = profile
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled, let self else { return }
            Log.write("relay: timed out")
            self.expiry = nil
            await self.finish()
        }
        keepLinks()
        Log.write("relay: on for \(profile)")
    }

    private static func takeLinks() async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL,
                                                           toOpenURLsWithScheme: LinkRouter.scheme)
    }

    /// A Claude copy that starts during the sign-in claims `claude://` back.
    /// Check once a second and take the links again when that happens.
    private func keepLinks() {
        watch?.cancel()
        watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.signingIn != nil else { return }
                guard let owner = Self.currentHandler(), !Self.same(owner, Bundle.main.bundleURL) else { continue }
                do {
                    try await Self.takeLinks()
                    Log.write("relay: \(owner.lastPathComponent) had claimed the links; took them back")
                } catch {
                    Log.write("relay: could not take the links back: \(error.localizedDescription)")
                }
            }
        }
    }

    func stop() async {
        expiry?.cancel()
        expiry = nil
        await finish()
    }

    private func finish() async {
        watch?.cancel()
        watch = nil
        if signingIn != nil { Log.write("relay: off") }
        signingIn = nil
        onSignInDelivered = nil
        await Self.returnLinks()
    }

    /// Give `claude://` back to whoever had it. Does nothing unless
    /// Switchboard is the handler, so it is safe at every launch (which is
    /// how a crash in the middle of a sign-in gets repaired).
    static func returnLinks() async {
        guard let owner = currentHandler(), same(owner, Bundle.main.bundleURL) else { return }
        let saved = UserDefaults.standard.string(forKey: previousHandlerKey).map { URL(fileURLWithPath: $0) }
        let candidates = [saved, ClaudeDesktop.appURL].compactMap { $0 }
        guard let target = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            Log.write("relay: no app to return claude:// links to")
            return
        }
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: target, toOpenURLsWithScheme: LinkRouter.scheme)
            UserDefaults.standard.removeObject(forKey: previousHandlerKey)
        } catch {
            Log.write("relay: could not return links: \(error.localizedDescription)")
        }
    }

    private static func currentHandler() -> URL? {
        URL(string: "\(LinkRouter.scheme)://").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    }

    private static func same(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.path == b.standardizedFileURL.path
    }

    // MARK: - Incoming links

    func handle(_ urls: [URL]) {
        Task { for url in urls { await route(url) } }
    }

    private func route(_ url: URL) async {
        let route = LinkRouter.route(url, signingIn: signingIn)
        Log.write("link \(LinkRouter.logLabel(for: url)) -> \(route)")
        switch route {
        case .ignore: return
        case .defaultClaude: await sendToDefault(url)
        case .signIn(let name):
            if await deliverSignIn(url, to: name) { onSignInDelivered?(name) }
        }
    }

    /// A sign-in link goes to exactly the account that asked, or nowhere.
    private func deliverSignIn(_ url: URL, to name: String) async -> Bool {
        while true {
            guard let profile = ProfileStore.shared.profile(named: name),
                  let app = ClaudeDesktop.running(profile) else {
                Log.write("relay: \(name) is not running; sign-in dropped")
                await stop()
                Dialogs.info("Sign-in was interrupted", "Claude was closed too early. Try again.")
                return false
            }
            do {
                try await Self.sendOpenURL(url, to: app.processIdentifier)
                Log.write("relay: delivered to \(name)")
                return true
            } catch {
                Log.write("relay: delivery to \(name) failed: \(error.localizedDescription)")
                switch Dialogs.deliveryFailed(name) {
                case .retry: continue
                case .openSettings:
                    Self.openAutomationSettings()
                    if Dialogs.confirm("Turn on “Claude” under Switchboard", button: "Try Again") { continue }
                    await stop(); return false
                case .cancel: await stop(); return false
                }
            }
        }
    }

    /// Any other link behaves as if Switchboard were not in the way.
    private func sendToDefault(_ url: URL) async {
        let fallback = Profile(name: Profile.defaultName, email: "", desktopSignedIn: true, cliDir: "", desktopDir: "")
        if let app = ClaudeDesktop.running(fallback),
           (try? await Self.sendOpenURL(url, to: app.processIdentifier)) != nil { return }
        guard let appURL = ClaudeDesktop.appURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = ClaudeDesktop.running(fallback) == nil
        _ = try? await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
    }

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Apple Events

    /// Send "open this link" to one specific process: the event macOS sends
    /// when you click a link, aimed at a single Claude copy. Off the main
    /// thread, because macOS may stop to ask for permission.
    static func sendOpenURL(_ url: URL, to pid: pid_t) async throws {
        let link = url.absoluteString
        try await Task.detached {
            let event = NSAppleEventDescriptor(
                eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
                targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            event.setParam(NSAppleEventDescriptor(string: link), forKeyword: keyDirectObject)
            _ = try event.sendEvent(options: [.noReply], timeout: 10)
        }.value
    }

    /// Ask for the Automation permission up front, so the prompt appears
    /// before the browser step and not in the middle of it.
    static func requestAutomationPermission(pid: pid_t) async -> Bool {
        await Task.detached {
            var target = AEAddressDesc()
            var p = pid
            guard AECreateDesc(DescType(typeKernelProcessID), &p, MemoryLayout<pid_t>.size, &target) == noErr
            else { return false }
            defer { AEDisposeDesc(&target) }
            return AEDeterminePermissionToAutomateTarget(
                &target, AEEventClass(kInternetEventClass), AEEventID(kAEGetURL), true) == noErr
        }.value
    }
}
