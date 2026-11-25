import Foundation
import SwitchboardCore

/// The accounts last read from disk. The menu draws from this copy at once
/// and refreshes it in the background.
@MainActor
final class ProfileStore {
    static let shared = ProfileStore()
    private(set) var profiles: [Profile] = []

    func profile(named name: String) -> Profile? { profiles.first { $0.name == name } }

    /// Reload from disk. Returns true if anything changed.
    @discardableResult
    func refresh() async -> Bool {
        let fresh = await Task.detached { AccountStore().profiles() }.value
        let changed = fresh != profiles
        profiles = fresh
        return changed
    }
}
