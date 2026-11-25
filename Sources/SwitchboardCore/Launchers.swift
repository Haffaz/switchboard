import Foundation

/// Opens a Terminal window that is set to one account.
public enum TerminalLauncher {
    public enum Mode: Sendable { case shell, claudeCode, signIn }

    /// The script the Terminal window runs. It is an interactive login
    /// shell, so `claude` is found the same way as when you type it.
    public static func script(name: String, exports: String, fallbackClaude: String?, mode: Mode) -> String {
        let run: String
        switch mode {
        case .shell: run = ""
        case .claudeCode: run = "cd ~ && run_claude"
        case .signIn: run = "run_claude auth login"
        }
        return """
            #!/bin/zsh -li
            clear
            \(exports)
            fallback=\(Shell.quote(fallbackClaude ?? ""))
            run_claude() {
              if command -v claude >/dev/null 2>&1; then claude "$@"
              elif [[ -n "$fallback" && -x "$fallback" ]]; then "$fallback" "$@"
              else print "Claude Code is not installed. See https://claude.com/claude-code"; fi
            }
            print -P "%BClaude account: \(name)%b\\n"
            \(run)
            exec "$SHELL" -l

            """
    }

    public static func open(_ name: String, mode: Mode, store: AccountStore = AccountStore()) throws {
        try store.require(name)
        let fm = FileManager.default
        let dir = store.paths.launchDir
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = dir.appendingPathComponent("\(name).command")
        let text = script(name: name, exports: store.shellExports(name),
                          fallbackClaude: ClaudeCode.find()?.path, mode: mode)
        try text.write(to: file, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        let app = ProcessInfo.processInfo.environment["CPROF_TERMINAL_APP"].flatMap { $0.isEmpty ? nil : $0 } ?? "Terminal"
        guard Shell.run("/usr/bin/open", ["-a", app, file.path]) == 0 else {
            throw SwitchboardError("could not open \(app)")
        }
    }
}

/// Makes a small "Claude (name).app" in ~/Applications that opens one
/// account's Claude Desktop, for the Dock.
public enum DockLauncher {
    @discardableResult
    public static func make(_ name: String, cprof: URL, claudeApp: URL?, store: AccountStore = AccountStore()) throws -> URL {
        try store.require(name)
        let fm = FileManager.default
        let app = store.paths.home.appendingPathComponent("Applications/Claude (\(name)).app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        let resources = app.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        if let icon = claudeApp?.appendingPathComponent("Contents/Resources/electron.icns") {
            let copy = resources.appendingPathComponent("icon.icns")
            try? fm.removeItem(at: copy)
            try? fm.copyItem(at: icon, to: copy)
        }
        let plist: [String: Any] = [
            "CFBundleName": "Claude (\(name))", "CFBundleIdentifier": "local.switchboard.launcher.\(name)",
            "CFBundleExecutable": "launch", "CFBundleIconFile": "icon", "CFBundlePackageType": "APPL",
            "LSUIElement": true,
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let launch = macOS.appendingPathComponent("launch")
        try "#!/bin/sh\nexec \(Shell.quote(cprof.path)) desktop \(Shell.quote(name))\n"
            .write(to: launch, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launch.path)
        return app
    }
}
