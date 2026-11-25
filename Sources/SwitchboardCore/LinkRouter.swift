import Foundation

/// Decides where a `claude://` link should go while Switchboard is relaying.
public enum LinkRouter {
    public static let scheme = "claude"

    public enum Kind: Equatable, Sendable { case signIn, other }

    public enum Route: Equatable, Sendable {
        /// Sign-in callback for the account that is signing in. It must reach
        /// exactly that account's Claude, or nowhere.
        case signIn(profile: String)
        /// Anything else behaves as if Switchboard were not there.
        case defaultClaude
        case ignore
    }

    /// Sign-in callbacks: Google (`claude://login/…`) and emailed links
    /// (`claude://claude.ai/magic-link…`).
    public static func kind(of url: URL) -> Kind {
        if url.host == "login" { return .signIn }
        let firstSegment = url.pathComponents.first { $0 != "/" }
        return firstSegment == "magic-link" ? .signIn : .other
    }

    public static func route(_ url: URL, signingIn: String?) -> Route {
        guard url.scheme?.lowercased() == scheme else { return .ignore }
        if kind(of: url) == .signIn, let signingIn { return .signIn(profile: signingIn) }
        return .defaultClaude
    }

    /// Safe to write to a log: never includes the path, query or fragment,
    /// any of which can carry a sign-in code.
    public static func logLabel(for url: URL) -> String {
        let host = url.host.map { $0.count > 40 ? "…" : $0 } ?? ""
        return "\(url.scheme ?? "?")://\(host) (\(kind(of: url) == .signIn ? "sign-in" : "other"))"
    }
}
