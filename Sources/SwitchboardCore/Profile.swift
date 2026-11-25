import Foundation

/// One account and what is known about it.
public struct Profile: Codable, Equatable, Sendable {
    public let name: String
    /// Email Claude Code is signed in with; empty if it is not signed in.
    /// Read from its settings file first (a fast guess), then corrected by
    /// `applying(_:)` once Claude Code has been asked.
    public let email: String
    public let desktopSignedIn: Bool
    public let cliDir: String
    /// Claude Desktop's data folder; empty for the default account.
    public let desktopDir: String
    /// Name of a monochrome system symbol chosen for this account, if any.
    public let icon: String?

    public init(name: String, email: String, desktopSignedIn: Bool, cliDir: String, desktopDir: String,
                icon: String? = nil) {
        self.icon = icon
        self.name = name
        self.email = email
        self.desktopSignedIn = desktopSignedIn
        self.cliDir = cliDir
        self.desktopDir = desktopDir
    }

    public var isDefault: Bool { name == Self.defaultName }
    public var displayName: String { isDefault ? "Default" : name }
    /// True when clicking the account should start sign-in, not just open it.
    public var needsDesktopSignIn: Bool { !isDefault && !desktopSignedIn }

    /// Section title in the menu: the name, plus who is signed in if known.
    public var sectionTitle: String {
        email.isEmpty ? displayName : "\(displayName) · \(email)"
    }

    public var codeSignedIn: Bool { !email.isEmpty }

    /// A copy corrected by what Claude Code itself reported. A signed-out
    /// account loses the email its settings file may still hold.
    public func applying(_ login: CodeLogin) -> Profile {
        let verified = login.signedIn ? (login.email.isEmpty ? (email.isEmpty ? "signed in" : email) : login.email) : ""
        return Profile(name: name, email: verified, desktopSignedIn: desktopSignedIn,
                       cliDir: cliDir, desktopDir: desktopDir, icon: icon)
    }

    /// The symbol to draw for this account: its own, or a neutral person.
    public var iconSymbol: String {
        guard let icon, AccountIcon.isValid(icon) else { return AccountIcon.fallback }
        return icon
    }

    public static let defaultName = "default"

    public static func decodeList(_ json: String) throws -> [Profile] {
        try JSONDecoder().decode([Profile].self, from: Data(json.utf8))
    }
}

public enum ProfileName {
    public static let maxLength = 32

    /// Lowercase letters, digits, '-' and '_'; starts with a letter or digit.
    public static func isValid(_ name: String) -> Bool {
        guard let first = name.first, name.count <= maxLength, first.isASCII, first.isLowercase || first.isNumber
        else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// Turn "Work Account" into "work-account". Nil if nothing usable is left.
    public static func slug(_ raw: String) -> String? {
        var result = ""
        for ch in raw.lowercased() {
            if ch.isASCII && (ch.isLetter || ch.isNumber) || ch == "_" {
                result.append(ch)
            } else if (ch == " " || ch == "-" || ch == ".") && !result.hasSuffix("-") {
                result.append("-")
            }
        }
        while let first = result.first, first == "-" || first == "_" { result.removeFirst() }
        result = String(result.prefix(maxLength))
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? nil : result
    }
}

/// Monochrome icons people can give an account, so accounts can be told
/// apart by shape. Names are Apple system symbols.
public enum AccountIcon {
    public static let fallback = "person.crop.circle"

    public static let choices: [(symbol: String, label: String)] = [
        ("briefcase", "Work"), ("house", "Home"), ("person", "Personal"), ("building.2", "Company"),
        ("graduationcap", "Study"), ("hammer", "Side project"), ("flask", "Experiments"), ("star", "Star"),
        ("heart", "Heart"), ("bolt", "Bolt"), ("leaf", "Leaf"), ("globe", "Globe"),
        ("book", "Book"), ("gamecontroller", "Games"), ("cart", "Shop"), ("lock", "Private"),
    ]

    /// Same rule as the CLI: lowercase letters, digits and dots.
    public static func isValid(_ symbol: String) -> Bool {
        !symbol.isEmpty && symbol.count <= 48 &&
            symbol.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == ".") }
    }
}
