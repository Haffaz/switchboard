import Foundation
import SwitchboardCore

/// The accounts last read from `cprof`. The menu draws from this copy at
/// once and refreshes it in the background.
@MainActor
final class ProfileStore {
    static let shared = ProfileStore()
    private(set) var profiles: [Profile] = []
    private(set) var loadError: String?

    func profile(named name: String) -> Profile? { profiles.first { $0.name == name } }

    /// Reload from disk. Returns true if anything changed.
    @discardableResult
    func refresh() async -> Bool {
        do {
            let fresh = try await Cprof.profiles()
            let changed = fresh != profiles || loadError != nil
            profiles = fresh
            loadError = nil
            return changed
        } catch {
            let changed = loadError != error.localizedDescription
            loadError = error.localizedDescription
            Log.write("could not load accounts: \(error.localizedDescription)")
            return changed
        }
    }
}
