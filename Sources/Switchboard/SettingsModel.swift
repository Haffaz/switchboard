import AppKit
import SwitchboardCore

/// What the Settings window shows, and the changes it can ask for. The
/// views read from here and never touch files themselves.
@MainActor
final class SettingsModel: ObservableObject {
    enum Tab: String, CaseIterable { case accounts = "Accounts", sharing = "Sharing", general = "General" }

    @Published var tab: Tab = .accounts
    @Published var selected: String = Profile.defaultName
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var running: Set<String> = []
    /// account -> thing -> the account it shares with
    @Published private(set) var sources: [String: [SharedThing: String]] = [:]
    @Published private(set) var opensAtLogin = false
    @Published private(set) var commandLineToolInstalled = false

    private let store = ProfileStore.shared

    var selectedProfile: Profile? { profiles.first { $0.name == selected } ?? profiles.first }
    /// The accounts that can be given a source: all but the default one.
    var sharingAccounts: [Profile] { profiles.filter { !$0.isDefault } }

    func source(_ thing: SharedThing, for profile: Profile) -> Profile? {
        sources[profile.name]?[thing].flatMap { name in profiles.first { $0.name == name } }
    }

    /// Accounts `profile` may share `thing` with: every other account, except
    /// any that would make history go round in a loop.
    func choices(_ thing: SharedThing, for profile: Profile) -> [Profile] {
        profiles.filter { candidate in
            guard candidate.name != profile.name else { return false }
            guard thing == .history else { return true }
            return root(of: candidate.name) != profile.name
        }
    }

    /// Accounts that take something from `profile`, for its own page.
    func sharesFrom(_ profile: Profile) -> [(thing: SharedThing, accounts: [Profile])] {
        SharedThing.allCases.compactMap { thing in
            let takers = profiles.filter { sources[$0.name]?[thing] == profile.name }
            return takers.isEmpty ? nil : (thing, takers)
        }
    }

    private func root(of name: String) -> String {
        var current = name, seen: Set<String> = [name]
        while let next = sources[current]?[.history], !seen.contains(next) { seen.insert(next); current = next }
        return current
    }

    /// Sample values for the documentation screenshots.
    func loadDemo(sources: [String: [SharedThing: String]]) {
        profiles = store.profiles
        running = store.runningNames()
        self.sources = sources
        opensAtLogin = true
        commandLineToolInstalled = true
    }

    /// Re-read everything from the app's current knowledge and from disk.
    func reload() async {
        guard !store.isDemo else { return }
        await store.refresh()
        profiles = store.profiles
        running = store.runningNames()
        if !profiles.contains(where: { $0.name == selected }) { selected = Profile.defaultName }
        let sharing = Sharing(store: Actions.accounts)
        sources = await Task.detached { sharing.sources() }.value
        opensAtLogin = Actions.opensAtLogin
        commandLineToolInstalled = Actions.commandLineToolInstalled
    }

    // MARK: - Changes

    func rename(_ profile: Profile, to name: String) { run { await Actions.rename(profile, to: name) } }
    func setIcon(_ profile: Profile, to symbol: String?) { run { await Actions.setIcon(profile, to: symbol) } }
    func signInDesktop(_ profile: Profile) { run { await Actions.signInDesktop(profile) } }
    func signInCode(_ profile: Profile) { run { await Actions.openTerminal(profile, .signIn) } }
    func makeDockApp(_ profile: Profile) { run { await Actions.makeDockApp(profile) } }
    func reveal(_ profile: Profile) { Actions.reveal(profile) }
    func remove(_ profile: Profile) { run { await Actions.remove(profile) } }
    func setSource(_ thing: SharedThing, for profile: Profile, to source: Profile?) {
        run { await Actions.setSharing(thing, for: profile, from: source) }
    }
    func installCommandLineTool() { run { await Actions.installCommandLineTool() } }

    func addAccount() {
        Task {
            if let name = await Actions.addAccount() { selected = name }
            await reload()
        }
    }

    func setOpensAtLogin(_ on: Bool) {
        Actions.setOpensAtLogin(on)
        opensAtLogin = store.isDemo ? on : Actions.opensAtLogin
    }

    /// Do something, then show its result.
    private func run(_ work: @escaping @MainActor () async -> Void) {
        Task {
            await work()
            await reload()
        }
    }
}
