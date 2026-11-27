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
    @Published private(set) var sharingOn: Set<SharedThing> = []
    @Published private(set) var sharingStatus: [SharedThing: String] = [:]
    @Published private(set) var opensAtLogin = false
    @Published private(set) var commandLineToolInstalled = false

    private let store = ProfileStore.shared

    var selectedProfile: Profile? { profiles.first { $0.name == selected } ?? profiles.first }
    /// What the default account is called, for "Shared from …".
    var sourceName: String { profiles.first { $0.isDefault }?.displayName ?? "Default" }

    /// Sample values for the documentation screenshots.
    func loadDemo(sharingOn: Set<SharedThing>, status: [SharedThing: String]) {
        profiles = store.profiles
        running = store.runningNames()
        self.sharingOn = sharingOn
        sharingStatus = status
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
        let (on, status) = await Task.detached {
            (sharing.enabled(), Dictionary(uniqueKeysWithValues: SharedThing.allCases.map { ($0, sharing.statusLine($0)) }))
        }.value
        sharingOn = on
        sharingStatus = status
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
    func setSharing(_ thing: SharedThing, on: Bool) { run { await Actions.setSharing(thing, on: on) } }
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
