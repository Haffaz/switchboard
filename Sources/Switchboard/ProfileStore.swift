import Foundation
import SwitchboardCore

/// The accounts as last known. The menu draws from this copy at once and
/// refreshes it in the background.
///
/// Reading the folders is instant. Asking Claude Code whether each account
/// is really signed in takes a moment, so that answer is kept and asked
/// again only when it is older than `loginMaxAge`, or after an action that
/// may have changed it.
@MainActor
final class ProfileStore {
    static let shared = ProfileStore()
    private static let loginMaxAge: TimeInterval = 10

    private(set) var profiles: [Profile] = []
    private var logins: [String: CodeLogin] = [:]
    private var loginsCheckedAt = Date.distantPast

    func profile(named name: String) -> Profile? { profiles.first { $0.name == name } }

    /// Reload from disk. Returns true if anything changed.
    @discardableResult
    func refresh(recheckLogins: Bool = false) async -> Bool {
        let accounts = AccountStore()
        let base = await Task.detached { accounts.profiles() }.value
        if recheckLogins || Date().timeIntervalSince(loginsCheckedAt) > Self.loginMaxAge {
            let names = base.map(\.name)
            logins = await Task.detached { accounts.codeLogins(names) }.value
            loginsCheckedAt = Date()
        }
        let fresh = base.map { profile in logins[profile.name].map(profile.applying) ?? profile }
        let changed = fresh != profiles
        profiles = fresh
        return changed
    }
}
