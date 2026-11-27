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
}

@Suite("Sharing settings")
struct SharingSettingsTests {
    @Test("Everything is off until switched on, and the choice is remembered")
    func offByDefault() throws {
        let box = try Sandbox()
        #expect(box.sharing.enabled().isEmpty)
        try box.sharing.set(.connectors, on: true)
        try box.sharing.set(.history, on: true)
        #expect(Sharing(store: box.store).enabled() == [.history, .connectors])
        try box.sharing.set(.history, on: false)
        #expect(box.sharing.enabled() == [.connectors])
    }

    @Test("The settings file is not mistaken for an account, and damage reads as all off")
    func settingsFileIsNotAnAccount() throws {
        let box = try Sandbox()
        try box.sharing.set(.history, on: true)
        #expect(box.store.names() == ["default"])
        try box.write("not json", to: box.store.paths.profilesHome.appendingPathComponent(".sharing.json"))
        #expect(box.sharing.enabled().isEmpty)
    }
}

@Suite("Sharing Claude Code history")
struct SharedHistoryTests {
    @Test("Other accounts link to the default account's history folders")
    func links() throws {
        let box = try Sandbox()
        try box.write("s1", to: box.defaultCLI.appendingPathComponent("projects/-repo/one.jsonl"))
        try box.store.add("work")
        try box.sharing.set(.history, on: true)
        let own = box.store.cliDir("work").appendingPathComponent("projects")
        #expect(box.linkTarget(own) == box.defaultCLI.appendingPathComponent("projects").path)
        #expect(box.read(own.appendingPathComponent("-repo/one.jsonl")) == "s1")
        // Folders the default account does not have are not invented.
        #expect(!box.exists(box.store.cliDir("work").appendingPathComponent("todos")))
        #expect(!box.exists(box.defaultCLI.appendingPathComponent("todos")))
    }

    @Test("Sessions an account already had are moved into the shared folder, not lost")
    func mergesExisting() throws {
        let box = try Sandbox()
        try box.write("default", to: box.defaultCLI.appendingPathComponent("projects/-repo/a.jsonl"))
        try box.store.add("work")
        let own = box.store.cliDir("work").appendingPathComponent("projects")
        try box.write("same repo", to: own.appendingPathComponent("-repo/b.jsonl"))
        try box.write("other repo", to: own.appendingPathComponent("-other/c.jsonl"))

        #expect(try box.sharing.set(.history, on: true).isEmpty)
        let shared = box.defaultCLI.appendingPathComponent("projects")
        #expect(box.read(shared.appendingPathComponent("-repo/a.jsonl")) == "default")
        #expect(box.read(shared.appendingPathComponent("-repo/b.jsonl")) == "same repo")
        #expect(box.read(shared.appendingPathComponent("-other/c.jsonl")) == "other repo")
        #expect(box.linkTarget(own) == shared.path)
    }

    @Test("A file that exists in both places is kept aside, never overwritten")
    func keepsClashesAside() throws {
        let box = try Sandbox()
        try box.write("default's", to: box.defaultCLI.appendingPathComponent("projects/-repo/same.jsonl"))
        try box.store.add("work")
        let cli = box.store.cliDir("work")
        try box.write("work's", to: cli.appendingPathComponent("projects/-repo/same.jsonl"))

        let notes = try box.sharing.set(.history, on: true)
        #expect(notes.count == 1)
        #expect(box.read(box.defaultCLI.appendingPathComponent("projects/-repo/same.jsonl")) == "default's")
        #expect(box.read(cli.appendingPathComponent("projects.before-sharing/-repo/same.jsonl")) == "work's")
        #expect(box.linkTarget(cli.appendingPathComponent("projects")) != nil)
    }

    @Test("An existing link is left alone, and a link pointing elsewhere is corrected")
    func relinking() throws {
        let box = try Sandbox()
        try box.write("s1", to: box.defaultCLI.appendingPathComponent("projects/-repo/one.jsonl"))
        try box.store.add("work")
        try box.sharing.set(.history, on: true)
        let own = box.store.cliDir("work").appendingPathComponent("projects")
        let created = try FileManager.default.attributesOfItem(atPath: own.path)[.creationDate] as? Date
        try box.sharing.apply()
        #expect(try FileManager.default.attributesOfItem(atPath: own.path)[.creationDate] as? Date == created)

        try FileManager.default.removeItem(at: own)
        try FileManager.default.createSymbolicLink(at: own, withDestinationURL: box.home)
        try box.sharing.apply()
        #expect(box.linkTarget(own) == box.defaultCLI.appendingPathComponent("projects").path)
    }

    @Test("Switching it off removes the links and leaves the history with the default account")
    func unlink() throws {
        let box = try Sandbox()
        try box.write("s1", to: box.defaultCLI.appendingPathComponent("projects/-repo/one.jsonl"))
        try box.store.add("work")
        try box.sharing.set(.history, on: true)
        try box.sharing.set(.history, on: false)
        #expect(!box.exists(box.store.cliDir("work").appendingPathComponent("projects")))
        #expect(box.read(box.defaultCLI.appendingPathComponent("projects/-repo/one.jsonl")) == "s1")
    }

    @Test("Applying twice changes nothing, and a new account picks the sharing up")
    func idempotentAndNewAccounts() throws {
        let box = try Sandbox()
        try box.write("s1", to: box.defaultCLI.appendingPathComponent("projects/-repo/one.jsonl"))
        try box.sharing.set(.history, on: true)
        try box.store.add("later")
        #expect(try box.sharing.apply().isEmpty)
        #expect(try box.sharing.apply().isEmpty)
        #expect(box.linkTarget(box.store.cliDir("later").appendingPathComponent("projects")) != nil)
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
        let file = box.store.cliDir("work").appendingPathComponent(".claude.json")
        try box.write(#"{"oauthAccount":{"emailAddress":"w@x.example"},"numStartups":7}"#, to: file)

        try box.sharing.set(.connectors, on: true)
        #expect(box.servers(file) == ["linear", "shared"])
        #expect(box.store.profile("work").email == "w@x.example")  // not the default account's
        #expect(box.json(file)?["numStartups"] as? Int == 7)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test("The account's own servers are kept; on a clash the default account's wins")
    func mergeRules() throws {
        let box = try Sandbox()
        try box.write(Self.defaultFile, to: box.store.paths.defaultCLIJSON)
        try box.store.add("work")
        let file = box.store.cliDir("work").appendingPathComponent(".claude.json")
        try box.write(#"{"mcpServers":{"mine":{"url":"mine"},"shared":{"url":"work"}}}"#, to: file)

        try box.sharing.set(.connectors, on: true)
        #expect(box.servers(file) == ["linear", "mine", "shared"])
        let shared = (box.json(file)?["mcpServers"] as? [String: Any])?["shared"] as? [String: String]
        #expect(shared?["url"] == "default")
    }

    @Test("Nothing is written when there is nothing new, or nothing to copy")
    func noNeedlessWrites() throws {
        let box = try Sandbox()
        try box.store.add("work")
        let file = box.store.cliDir("work").appendingPathComponent(".claude.json")
        try box.sharing.set(.connectors, on: true)
        #expect(!box.exists(file))  // the default account has no servers

        try box.write(Self.defaultFile, to: box.store.paths.defaultCLIJSON)
        #expect(try box.sharing.syncConnectors("work"))
        #expect(try !box.sharing.syncConnectors("work"))
    }

    @Test("The default account's file is only read")
    func defaultIsNotChanged() throws {
        let box = try Sandbox()
        try box.write(Self.defaultFile, to: box.store.paths.defaultCLIJSON)
        try box.store.add("work")
        try box.sharing.set(.connectors, on: true)
        #expect(box.read(box.store.paths.defaultCLIJSON) == Self.defaultFile)
    }
}

@Suite("Sharing Claude Desktop extensions")
struct SharedExtensionsTests {
    func installExtension(_ box: Sandbox, _ id: String, registry: String) throws {
        try box.write("code", to: box.defaultDesktop.appendingPathComponent("Claude Extensions/\(id)/server.js"))
        try box.write(#"{"isEnabled":true}"#, to: box.defaultDesktop.appendingPathComponent("Claude Extensions Settings/\(id).json"))
        try box.write(registry, to: box.defaultDesktop.appendingPathComponent("extensions-installations.json"))
    }

    @Test("Extensions are copied into an account before its Claude Desktop starts")
    func copies() throws {
        let box = try Sandbox()
        try installExtension(box, "ext.one", registry: #"{"extensions":{"ext.one":{}}}"#)
        try box.store.add("work")
        try box.sharing.set(.extensions, on: true)
        let desktop = box.store.desktopDir("work")!

        #expect(try box.sharing.prepareDesktop("work"))
        #expect(box.read(desktop.appendingPathComponent("Claude Extensions/ext.one/server.js")) == "code")
        #expect(box.exists(desktop.appendingPathComponent("Claude Extensions Settings/ext.one.json")))
        #expect(box.linkTarget(desktop.appendingPathComponent("Claude Extensions")) == nil)  // a copy, not a link
        #expect(try !box.sharing.prepareDesktop("work"))  // already up to date
    }

    @Test("A change in the default account is picked up; the default account is never written")
    func followsDefault() throws {
        let box = try Sandbox()
        try installExtension(box, "ext.one", registry: #"{"extensions":{"ext.one":{}}}"#)
        try box.store.add("work")
        try box.sharing.set(.extensions, on: true)
        try box.sharing.prepareDesktop("work")
        let desktop = box.store.desktopDir("work")!
        try box.write("changed in work", to: desktop.appendingPathComponent("Claude Extensions/ext.one/server.js"))

        try installExtension(box, "ext.two", registry: #"{"extensions":{"ext.one":{},"ext.two":{}}}"#)
        #expect(try box.sharing.prepareDesktop("work"))
        #expect(box.exists(desktop.appendingPathComponent("Claude Extensions/ext.two/server.js")))
        #expect(box.read(desktop.appendingPathComponent("Claude Extensions/ext.one/server.js")) == "code")
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
        try box.sharing.set(.extensions, on: true)

        #expect(try box.sharing.prepareDesktop("work"))
        #expect(box.servers(config) == ["files"])
        #expect((box.json(config)?["preferences"] as? [String: String])?["theme"] == "light")
    }

    @Test("Nothing happens when the sharing is off, or for the default account")
    func offOrDefault() throws {
        let box = try Sandbox()
        try installExtension(box, "ext.one", registry: #"{"extensions":{"ext.one":{}}}"#)
        try box.store.add("work")
        #expect(try !box.sharing.prepareDesktop("work"))
        #expect(!box.exists(box.store.desktopDir("work")!.appendingPathComponent("Claude Extensions")))
        try box.sharing.set(.extensions, on: true)
        #expect(try !box.sharing.prepareDesktop("default"))
    }
}
