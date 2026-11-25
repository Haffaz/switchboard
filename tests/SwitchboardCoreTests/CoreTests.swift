import Foundation
import Testing
@testable import SwitchboardCore

@Suite("Account names")
struct ProfileNameTests {
    @Test("Cleans up what people type", arguments: [
        ("Work", "work"), ("Work Account", "work-account"), ("  Client: ACME Inc. ", "client-acme-inc"),
        ("my_side_project", "my_side_project"), ("über-team", "ber-team"), ("--x--", "x"),
    ])
    func slug(input: String, expected: String) {
        #expect(ProfileName.slug(input) == expected)
    }

    @Test("Rejects names with nothing usable", arguments: ["", "---", "   ", "日本"])
    func rejects(input: String) {
        #expect(ProfileName.slug(input) == nil)
    }

    @Test("Caps the length without a trailing dash")
    func capsLength() {
        let slug = ProfileName.slug(String(repeating: "a", count: 31) + " b")
        #expect(slug == String(repeating: "a", count: 31))
    }
}

@Suite("Profiles")
struct ProfileTests {
    static let json = """
        [{"name":"default","email":"me@x.example","desktopRunning":true,"desktopSignedIn":true,"cliDir":"/h/.claude","desktopDir":""},
         {"name":"work","email":"","desktopRunning":false,"desktopSignedIn":false,"cliDir":"/h/p/work/cli","desktopDir":"/h/p/work/desktop"}]
        """

    @Test("Decodes the CLI's JSON, ignoring fields it does not need")
    func decodes() throws {
        let profiles = try Profile.decodeList(Self.json)
        #expect(profiles.map(\.name) == ["default", "work"])
        #expect(profiles[0].isDefault && !profiles[0].needsDesktopSignIn)
        #expect(profiles[1].needsDesktopSignIn)
        #expect(profiles[0].sectionTitle == "Default · me@x.example")
        #expect(profiles[1].sectionTitle == "work")
        #expect(profiles[0].codeSignedIn && !profiles[1].codeSignedIn)
    }

    @Test("Icon falls back to a neutral person when unset or invalid", arguments: [
        (nil, "person.crop.circle"), ("", "person.crop.circle"), ("Bad Icon!", "person.crop.circle"),
        ("briefcase", "briefcase"), ("building.2", "building.2"),
    ] as [(String?, String)])
    func icon(stored: String?, expected: String) {
        let p = Profile(name: "work", email: "", desktopSignedIn: true, cliDir: "", desktopDir: "/d", icon: stored)
        #expect(p.iconSymbol == expected)
    }

    @Test("Every offered icon passes the same rule the CLI enforces")
    func choicesAreValid() {
        #expect(AccountIcon.choices.allSatisfy { AccountIcon.isValid($0.symbol) })
        #expect(Set(AccountIcon.choices.map(\.symbol)).count == AccountIcon.choices.count)
    }

    @Test("Default never asks for Desktop sign-in")
    func defaultNeverNeedsSignIn() {
        let p = Profile(name: "default", email: "", desktopSignedIn: false, cliDir: "", desktopDir: "")
        #expect(!p.needsDesktopSignIn)
    }
}

@Suite("Process arguments")
struct ProcessArgumentsTests {
    static func procargs(_ exe: String, _ args: [String], env: [String] = ["HOME=/h"]) -> [UInt8] {
        var bytes = withUnsafeBytes(of: Int32(args.count)) { Array($0) }
        bytes += Array(exe.utf8) + [0, 0, 0]
        for item in args + env { bytes += Array(item.utf8) + [0] }
        return bytes
    }

    let work = Profile(name: "work", email: "", desktopSignedIn: true, cliDir: "", desktopDir: "/h/my profiles/work/desktop")
    let fallback = Profile(name: "default", email: "", desktopSignedIn: true, cliDir: "", desktopDir: "")

    @Test("Parses arguments and stops before the environment")
    func parses() {
        let args = ProcessArguments.parse(Self.procargs("/A/Claude", ["/A/Claude", "--user-data-dir=/x y/z", "--flag"]))
        #expect(args == ["/A/Claude", "--user-data-dir=/x y/z", "--flag"])
    }

    @Test("Rejects truncated or empty data")
    func rejectsGarbage() {
        #expect(ProcessArguments.parse([]) == nil)
        #expect(ProcessArguments.parse([9, 0, 0, 0, 65, 0]) == nil)
    }

    @Test("Matches a copy to its account, even with spaces in the folder")
    func matches() {
        let args = ["/A/Claude", "--user-data-dir=/h/my profiles/work/desktop/"]
        #expect(ProcessArguments.belongs(args, to: work))
        #expect(!ProcessArguments.belongs(args, to: fallback))
    }

    @Test("A copy with no data-folder flag is the default account")
    func defaultCopy() {
        #expect(ProcessArguments.belongs(["/A/Claude"], to: fallback))
        #expect(!ProcessArguments.belongs(["/A/Claude"], to: work))
    }

    @Test("Reads this test process's own arguments")
    func readsLiveProcess() {
        let args = ProcessArguments.of(pid: getpid())
        #expect(args?.isEmpty == false)
    }
}

@Suite("Link routing")
struct LinkRouterTests {
    @Test("Sign-in links go only to the account signing in", arguments: [
        "claude://login/google-auth?code=SECRET", "claude://claude.ai/magic-link#SECRET:abc",
    ])
    func signIn(link: String) throws {
        let url = try #require(URL(string: link))
        #expect(LinkRouter.route(url, signingIn: "work") == .signIn(profile: "work"))
        #expect(LinkRouter.route(url, signingIn: nil) == .defaultClaude)
    }

    @Test("Other links always go to the default Claude", arguments: [
        "claude://claude.ai/chat/123", "claude://code/resume?id=1", "claude://claude.ai/settings/magic-link",
    ])
    func other(link: String) throws {
        let url = try #require(URL(string: link))
        #expect(LinkRouter.route(url, signingIn: "work") == .defaultClaude)
    }

    @Test("Links for other apps are ignored")
    func foreignScheme() throws {
        #expect(LinkRouter.route(try #require(URL(string: "https://claude.ai/login")), signingIn: "work") == .ignore)
    }

    @Test("Log labels never contain codes", arguments: [
        "claude://login/google-auth?code=SECRET", "claude://claude.ai/magic-link#SECRET:abc",
        "claude://claude.ai/SECRET/path?x=SECRET",
    ])
    func logLabel(link: String) throws {
        let label = LinkRouter.logLabel(for: try #require(URL(string: link)))
        #expect(!label.contains("SECRET"))
        #expect(!label.contains("google-auth"))
    }
}
