import Foundation
import Testing
@testable import SwitchboardCore

extension Sandbox {
    var sharing: Sharing { Sharing(store: store) }
    var defaultCLI: URL { store.paths.defaultCLIDir }
    var defaultDesktop: URL { store.paths.defaultDesktopDir }

    func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    func json(_ url: URL) -> [String: Any]? {
        (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    }

    func servers(_ url: URL) -> [String] {
        ((json(url)?["mcpServers"] as? [String: Any]) ?? [:]).keys.sorted()
    }

    func cliJSON(_ name: String) -> URL { store.cliDir(name).appendingPathComponent(".claude.json") }
    func projects(_ name: String) -> URL { store.cliDir(name).appendingPathComponent("projects") }
}

@Suite("Who shares with whom")
struct SharingPlanTests {
    @Test("Nothing is shared until chosen, per account and per thing")
    func perAccount() throws {
        let box = try Sandbox()
        try box.store.add("work"); try box.store.add("client"); try box.store.add("home")
        #expect(box.sharing.sources().isEmpty)
        try box.sharing.setSource(.connectors, for: "client", to: "work")
        try box.sharing.setSource(.history, for: "work", to: "default")
        #expect(box.sharing.source(.connectors, for: "client") == "work")
        #expect(box.sharing.source(.history, for: "client") == nil)
        #expect(box.sharing.source(.history, for: "work") == "default")
        #expect(box.sharing.sources()["home"] == nil)
        #expect(box.sharing.dependents(of: "work", for: .connectors) == ["client"])
    }

    @Test("The default account can be shared from, never shared into", arguments: SharedThing.allCases)
    func defaultIsOnlyASource(thing: SharedThing) throws {
        let box = try Sandbox()
        try box.store.add("work")
        #expect(throws: SwitchboardError.self) { try box.sharing.setSource(thing, for: "default", to: "work") }
        #expect(throws: SwitchboardError.self) { try box.sharing.setSource(thing, for: "work", to: "work") }
        #expect(throws: SwitchboardError.self) { try box.sharing.setSource(thing, for: "work", to: "ghost") }
        try box.sharing.setSource(thing, for: "work", to: "default")
        #expect(box.sharing.source(thing, for: "work") == "default")
    }

    @Test("History can chain, but never loop")
    func noLoops() throws {
        let box = try Sandbox()
        try box.store.add("a"); try box.store.add("b"); try box.store.add("c")
        try box.sharing.setSource(.history, for: "a", to: "b")
        try box.sharing.setSource(.history, for: "b", to: "c")
        #expect(box.sharing.historyRoot(of: "a") == "c")
        #expect(box.sharing.historySharers(of: "c") == ["a", "b"])
        #expect(box.sharing.refusal(.history, for: "c", from: "a") != nil)
        #expect(throws: SwitchboardError.self) { try box.sharing.setSource(.history, for: "c", to: "a") }
        // Copies can point both ways without harm.
        try box.sharing.setSource(.connectors, for: "a", to: "c")
        try box.sharing.setSource(.connectors, for: "c", to: "a")
    }

    @Test("Removing an account forgets copies taken from it")
    func forget() throws {
        let box = try Sandbox()
        try box.store.add("work"); try box.store.add("client")
        try box.sharing.setSource(.connectors, for: "client", to: "work")
        try box.sharing.setSource(.extensions, for: "work", to: "default")
        try box.sharing.forget("work")
        #expect(box.sharing.sources().isEmpty)
    }

    @Test("A damaged settings file reads as nothing shared; the first form is still understood")
    func reading() throws {
        let box = try Sandbox()
        try box.store.add("work")
        let file = box.store.paths.profilesHome.appendingPathComponent(".sharing.json")
        try box.write("not json", to: file)
        #expect(box.sharing.sources().isEmpty)
        try box.write(#"["connectors"]"#, to: file)
        #expect(box.sharing.source(.connectors, for: "work") == "default")
        #expect(box.store.names() == ["default", "work"])  // the settings file is not an account
    }
}

@Suite("Same as Default")
struct SameAsDefaultTests {
    @Test("One switch shares all three with the default account, and switches them all off")
    func allThree() throws {
        let box = try Sandbox()
        try box.write("s1", to: box.defaultCLI.appendingPathComponent("projects/-repo/one.jsonl"))
        try box.store.add("work")
        #expect(!box.sharing.isSameAsDefault("work"))

        try box.sharing.setSameAsDefault("work", true)
        #expect(box.sharing.isSameAsDefault("work"))
        for thing in SharedThing.allCases { #expect(box.sharing.source(thing, for: "work") == "default") }
        #expect(box.linkTarget(box.projects("work")) == box.defaultCLI.appendingPathComponent("projects").path)

        try box.sharing.setSameAsDefault("work", false)
        #expect(box.sharing.sources()["work"] == nil)
        #expect(!box.exists(box.projects("work")))
        #expect(box.read(box.defaultCLI.appendingPathComponent("projects/-repo/one.jsonl")) == "s1")
    }

    @Test("Changing one thing afterwards means it is no longer the same as Default")
    func partly() throws {
        let box = try Sandbox()
        try box.store.add("work"); try box.store.add("client")
        try box.sharing.setSameAsDefault("work", true)
        try box.sharing.setSource(.connectors, for: "work", to: "client")
        #expect(!box.sharing.isSameAsDefault("work"))
    }

    @Test("Not for the default account itself")
    func notForDefault() throws {
        let box = try Sandbox()
        #expect(throws: SwitchboardError.self) { try box.sharing.setSameAsDefault("default", true) }
        #expect(!box.sharing.isSameAsDefault("default"))
    }
}

@Suite("Sharing Claude Code history")
struct SharedHistoryTests {
    @Test("An account links to its source's history folders")
    func links() throws {
        let box = try Sandbox()
        try box.write("s1", to: box.defaultCLI.appendingPathComponent("projects/-repo/one.jsonl"))
        try box.store.add("work")
        try box.sharing.setSource(.history, for: "work", to: "default")
        #expect(box.linkTarget(box.projects("work")) == box.defaultCLI.appendingPathComponent("projects").path)
        #expect(box.read(box.projects("work").appendingPathComponent("-repo/one.jsonl")) == "s1")
        // The default account's missing folders are not invented.
        #expect(!box.exists(box.defaultCLI.appendingPathComponent("todos")))
    }

    @Test("Two added accounts can share with each other, leaving the default account alone")
    func betweenAddedAccounts() throws {
        let box = try Sandbox()
        try box.store.add("work"); try box.store.add("client")
        try box.write("client's", to: box.projects("client").appendingPathComponent("-c/x.jsonl"))
        try box.sharing.setSource(.history, for: "client", to: "work")
        #expect(box.linkTarget(box.projects("client")) == box.projects("work").path)
        #expect(box.read(box.projects("work").appendingPathComponent("-c/x.jsonl")) == "client's")
        #expect(!box.exists(box.defaultCLI.appendingPathComponent("projects")))
    }

    @Test("A chain shares one folder: the end of the chain's")
    func chains() throws {
        let box = try Sandbox()
        try box.store.add("a"); try box.store.add("b"); try box.store.add("c")
        try box.write("from a", to: box.projects("a").appendingPathComponent("-r/a.jsonl"))
        try box.sharing.setSource(.history, for: "a", to: "b")
        try box.sharing.setSource(.history, for: "b", to: "c")
        #expect(box.linkTarget(box.projects("a")) == box.projects("c").path)
        #expect(box.linkTarget(box.projects("b")) == box.projects("c").path)
        #expect(box.read(box.projects("c").appendingPathComponent("-r/a.jsonl")) == "from a")
    }

    @Test("Sessions an account already had are moved in, not lost")
    func mergesExisting() throws {
        let box = try Sandbox()
        try box.write("default", to: box.defaultCLI.appendingPathComponent("projects/-repo/a.jsonl"))
        try box.store.add("work")
        try box.write("same repo", to: box.projects("work").appendingPathComponent("-repo/b.jsonl"))
        try box.write("other repo", to: box.projects("work").appendingPathComponent("-other/c.jsonl"))

        #expect(try box.sharing.setSource(.history, for: "work", to: "default").isEmpty)
        let shared = box.defaultCLI.appendingPathComponent("projects")
        #expect(box.read(shared.appendingPathComponent("-repo/a.jsonl")) == "default")
        #expect(box.read(shared.appendingPathComponent("-repo/b.jsonl")) == "same repo")
        #expect(box.read(shared.appendingPathComponent("-other/c.jsonl")) == "other repo")
    }

    @Test("A file that exists in both places is kept aside, never overwritten")
    func keepsClashesAside() throws {
        let box = try Sandbox()
        try box.write("default's", to: box.defaultCLI.appendingPathComponent("projects/-repo/same.jsonl"))
        try box.store.add("work")
        try box.write("work's", to: box.projects("work").appendingPathComponent("-repo/same.jsonl"))

        #expect(try box.sharing.setSource(.history, for: "work", to: "default").count == 1)
        #expect(box.read(box.defaultCLI.appendingPathComponent("projects/-repo/same.jsonl")) == "default's")
        let aside = box.store.cliDir("work").appendingPathComponent("projects.before-sharing/-repo/same.jsonl")
        #expect(box.read(aside) == "work's")
    }

    @Test("Stopping removes the links; the shared sessions stay with the source")
    func stop() throws {
        let box = try Sandbox()
        try box.write("s1", to: box.defaultCLI.appendingPathComponent("projects/-repo/one.jsonl"))
        try box.store.add("work")
        try box.sharing.setSource(.history, for: "work", to: "default")
        try box.sharing.setSource(.history, for: "work", to: nil)
        #expect(!box.exists(box.projects("work")))
        #expect(box.read(box.defaultCLI.appendingPathComponent("projects/-repo/one.jsonl")) == "s1")
    }

    @Test("Switching source moves the account's link; applying again changes nothing")
    func switching() throws {
        let box = try Sandbox()
        try box.write("d", to: box.defaultCLI.appendingPathComponent("projects/-d/d.jsonl"))
        try box.store.add("work"); try box.store.add("client")
        try box.sharing.setSource(.history, for: "client", to: "default")
        try box.sharing.setSource(.history, for: "client", to: "work")
        #expect(box.linkTarget(box.projects("client")) == box.projects("work").path)
        #expect(try box.sharing.apply().isEmpty)
        #expect(box.linkTarget(box.projects("client")) == box.projects("work").path)
    }

    @Test("Removing an account that shares into another deletes links, not the shared sessions")
    func removingADependent() throws {
        let box = try Sandbox()
        try box.write("s1", to: box.defaultCLI.appendingPathComponent("projects/-repo/one.jsonl"))
        try box.store.add("work")
        try box.sharing.setSource(.history, for: "work", to: "default")
        try box.store.remove("work")
        #expect(box.read(box.defaultCLI.appendingPathComponent("projects/-repo/one.jsonl")) == "s1")
    }
}

@Suite("Sharing Claude Code connectors")
struct SharedConnectorsTests {
    static let defaultFile = #"{"oauthAccount":{"emailAddress":"d@x.example"},"mcpServers":{"linear":{"type":"http","url":"https://l.example"},"shared":{"url":"default"}}}"#

    @Test("Servers are copied; the account's sign-in and other settings are untouched")
    func copiesOnlyServers() throws {
        let box = try Sandbox()
        try box.write(Self.defaultFile, to: box.store.paths.defaultCLIJSON)
        try box.store.add("work")
        try box.write(#"{"oauthAccount":{"emailAddress":"w@x.example"},"numStartups":7}"#, to: box.cliJSON("work"))

        try box.sharing.setSource(.connectors, for: "work", to: "default")
        #expect(box.servers(box.cliJSON("work")) == ["linear", "shared"])
        #expect(box.store.profile("work").email == "w@x.example")  // not the source's
        #expect(box.json(box.cliJSON("work"))?["numStartups"] as? Int == 7)
        let mode = try FileManager.default.attributesOfItem(atPath: box.cliJSON("work").path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(box.read(box.store.paths.defaultCLIJSON) == Self.defaultFile)  // the source is only read
    }

    @Test("Copied from the chosen account only, not from the default account")
    func fromChosenAccount() throws {
        let box = try Sandbox()
        try box.write(Self.defaultFile, to: box.store.paths.defaultCLIJSON)
        try box.store.add("work"); try box.store.add("client")
        try box.write(#"{"mcpServers":{"jira":{"url":"j"}}}"#, to: box.cliJSON("work"))
        try box.sharing.setSource(.connectors, for: "client", to: "work")
        #expect(box.servers(box.cliJSON("client")) == ["jira"])
    }

    @Test("The account's own servers are kept; on a clash the source wins")
    func mergeRules() throws {
        let box = try Sandbox()
        try box.write(Self.defaultFile, to: box.store.paths.defaultCLIJSON)
        try box.store.add("work")
        try box.write(#"{"mcpServers":{"mine":{"url":"mine"},"shared":{"url":"work"}}}"#, to: box.cliJSON("work"))

        try box.sharing.setSource(.connectors, for: "work", to: "default")
        #expect(box.servers(box.cliJSON("work")) == ["linear", "mine", "shared"])
        let shared = (box.json(box.cliJSON("work"))?["mcpServers"] as? [String: Any])?["shared"] as? [String: String]
        #expect(shared?["url"] == "default")
    }

    @Test("Nothing is written when there is nothing new, or nothing to copy")
    func noNeedlessWrites() throws {
        let box = try Sandbox()
        try box.store.add("work")
        try box.sharing.setSource(.connectors, for: "work", to: "default")
        #expect(!box.exists(box.cliJSON("work")))  // the source has no servers
        try box.write(Self.defaultFile, to: box.store.paths.defaultCLIJSON)
        #expect(try box.sharing.syncConnectors("work", from: "default"))
        #expect(try !box.sharing.syncConnectors("work", from: "default"))
    }
}

@Suite("Sharing Claude Desktop extensions")
struct SharedExtensionsTests {
    func installExtension(_ box: Sandbox, in folder: URL, _ id: String, registry: String) throws {
        try box.write("code", to: folder.appendingPathComponent("Claude Extensions/\(id)/server.js"))
        try box.write(#"{"isEnabled":true}"#, to: folder.appendingPathComponent("Claude Extensions Settings/\(id).json"))
        try box.write(registry, to: folder.appendingPathComponent("extensions-installations.json"))
    }

    @Test("Extensions are copied from the chosen account before Claude Desktop starts")
    func copies() throws {
        let box = try Sandbox()
        try installExtension(box, in: box.defaultDesktop, "ext.one", registry: #"{"extensions":{"ext.one":{}}}"#)
        try box.store.add("work")
        try box.sharing.setSource(.extensions, for: "work", to: "default")
        let desktop = box.store.desktopDir("work")!

        #expect(try box.sharing.prepareDesktop("work"))
        #expect(box.read(desktop.appendingPathComponent("Claude Extensions/ext.one/server.js")) == "code")
        #expect(box.linkTarget(desktop.appendingPathComponent("Claude Extensions")) == nil)  // a copy, not a link
        #expect(try !box.sharing.prepareDesktop("work"))  // already up to date
    }

    @Test("They can come from an added account too")
    func fromAddedAccount() throws {
        let box = try Sandbox()
        try box.store.add("work"); try box.store.add("client")
        try installExtension(box, in: box.store.desktopDir("work")!, "ext.w", registry: #"{"extensions":{"ext.w":{}}}"#)
        try box.sharing.setSource(.extensions, for: "client", to: "work")
        #expect(try box.sharing.prepareDesktop("client"))
        #expect(box.exists(box.store.desktopDir("client")!.appendingPathComponent("Claude Extensions/ext.w/server.js")))
    }

    @Test("A change at the source is picked up; the source is never written")
    func followsSource() throws {
        let box = try Sandbox()
        try installExtension(box, in: box.defaultDesktop, "ext.one", registry: #"{"extensions":{"ext.one":{}}}"#)
        try box.store.add("work")
        try box.sharing.setSource(.extensions, for: "work", to: "default")
        try box.sharing.prepareDesktop("work")
        let desktop = box.store.desktopDir("work")!
        try box.write("changed in work", to: desktop.appendingPathComponent("Claude Extensions/ext.one/server.js"))

        try installExtension(box, in: box.defaultDesktop, "ext.two", registry: #"{"extensions":{"ext.one":{},"ext.two":{}}}"#)
        #expect(try box.sharing.prepareDesktop("work"))
        #expect(box.exists(desktop.appendingPathComponent("Claude Extensions/ext.two/server.js")))
        #expect(box.read(box.defaultDesktop.appendingPathComponent("Claude Extensions/ext.one/server.js")) == "code")
    }

    @Test("Local MCP servers in Desktop's settings are merged; its other settings are kept")
    func mergesDesktopServers() throws {
        let box = try Sandbox()
        try box.write(#"{"mcpServers":{"files":{"command":"x"}},"preferences":{"theme":"dark"}}"#,
                      to: box.defaultDesktop.appendingPathComponent("claude_desktop_config.json"))
        try box.store.add("work")
        let config = box.store.desktopDir("work")!.appendingPathComponent("claude_desktop_config.json")
        try box.write(#"{"preferences":{"theme":"light"}}"#, to: config)
        try box.sharing.setSource(.extensions, for: "work", to: "default")

        #expect(try box.sharing.prepareDesktop("work"))
        #expect(box.servers(config) == ["files"])
        #expect((box.json(config)?["preferences"] as? [String: String])?["theme"] == "light")
    }

    @Test("Nothing happens without a source, or for the default account")
    func noSource() throws {
        let box = try Sandbox()
        try installExtension(box, in: box.defaultDesktop, "ext.one", registry: #"{"extensions":{"ext.one":{}}}"#)
        try box.store.add("work")
        #expect(try !box.sharing.prepareDesktop("work"))
        #expect(try !box.sharing.prepareDesktop("default"))
    }
}
