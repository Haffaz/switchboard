import AppKit
import SwiftUI
import SwitchboardCore

/// The Settings window: one place for everything that is rare or needs a
/// line of explanation. Opened with "Settings…" in the menu.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    static let size = NSSize(width: 660, height: 600)

    let model = SettingsModel()
    private(set) var window: NSWindow?

    func show(_ tab: SettingsModel.Tab? = nil) {
        if let tab { model.tab = tab }
        let window = window ?? makeWindow()
        self.window = window
        Task { await model.reload() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = "Switchboard Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(Self.size)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    /// Coming back to the window shows the current state, for example after
    /// signing in elsewhere.
    func windowDidBecomeKey(_ notification: Notification) {
        Task { await model.reload() }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView(selection: $model.tab) {
            AccountsPane(model: model)
                .tabItem { Label("Accounts", systemImage: "person.2") }.tag(SettingsModel.Tab.accounts)
            SharingPane(model: model)
                .tabItem { Label("Sharing", systemImage: "arrow.triangle.branch") }.tag(SettingsModel.Tab.sharing)
            GeneralPane(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsModel.Tab.general)
        }
        .padding(.top, 10)
        .frame(width: SettingsWindow.size.width, height: SettingsWindow.size.height)
    }
}

// MARK: - Accounts

private struct AccountsPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $model.selected) {
                    ForEach(model.profiles, id: \.name) { profile in
                        HStack(spacing: 8) {
                            Image(systemName: profile.iconSymbol).frame(width: 18)
                            Text(profile.displayName).lineLimit(1)
                            Spacer(minLength: 4)
                            if model.running.contains(profile.name) {
                                Circle().fill(.green).frame(width: 7, height: 7).help("Claude Desktop is running")
                            }
                        }
                        .tag(profile.name)
                    }
                }
                Divider()
                HStack(spacing: 2) {
                    Button { model.addAccount() } label: { Image(systemName: "plus").frame(width: 22, height: 18) }
                        .help("Add an account")
                    Button {
                        if let profile = model.selectedProfile { model.remove(profile) }
                    } label: { Image(systemName: "minus").frame(width: 22, height: 18) }
                        .disabled(model.selectedProfile?.isDefault ?? true)
                        .help("Remove this account")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 190)
            Divider()
            if let profile = model.selectedProfile {
                AccountDetail(model: model, profile: profile).id(profile.name)
            } else {
                Spacer()
            }
        }
    }
}

private struct AccountDetail: View {
    @ObservedObject var model: SettingsModel
    let profile: Profile
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private func saveName() {
        guard name != profile.displayName else { return }
        model.rename(profile, to: name)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                    .onSubmit { saveName() }
                LabeledContent("Icon") { IconPicker(selected: profile.icon) { model.setIcon(profile, to: $0) } }
            } footer: {
                if profile.isDefault {
                    Note("This is the Claude setup you had before Switchboard. It is never moved or changed.")
                }
            }
            Section("Sign-in") {
                LabeledContent("Claude Desktop") {
                    if profile.isDefault {
                        Text("Your usual sign-in").foregroundStyle(.secondary)
                    } else {
                        Text(profile.desktopSignedIn ? "Signed in" : "Not signed in").foregroundStyle(.secondary)
                        Button(profile.desktopSignedIn ? "Sign In Again…" : "Sign In…") { model.signInDesktop(profile) }
                    }
                }
                LabeledContent("Claude Code") {
                    Text(profile.codeSignedIn ? profile.email : "Not signed in").foregroundStyle(.secondary).lineLimit(1)
                    Button(profile.codeSignedIn ? "Sign In Again…" : "Sign In…") { model.signInCode(profile) }
                }
            }
            Section {
                if profile.isDefault {
                    let shared = model.sharesFrom(profile)
                    if shared.isEmpty {
                        Text("No account shares from this one yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(shared, id: \.thing) { entry in
                            LabeledContent(entry.thing.title) {
                                Text(entry.accounts.map(\.displayName).joined(separator: ", ")).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    ForEach(SharedThing.allCases, id: \.self) { thing in
                        LabeledContent(thing.title) {
                            SourcePicker(model: model, profile: profile, thing: thing).frame(width: 150)
                        }
                        .help(thing.summary)
                    }
                }
            } header: {
                Text(profile.isDefault ? "Shared from this account" : "Share with")
            }
            Section {
                HStack {
                    if !profile.isDefault { Button("Add Dock Icon") { model.makeDockApp(profile) } }
                    Button("Show Files") { model.reveal(profile) }
                    Spacer()
                    if !profile.isDefault { Button("Remove Account…", role: .destructive) { model.remove(profile) } }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { name = profile.displayName }
        // Leaving the field, or picking another account, saves the name too.
        .onDisappear { saveName() }
        .onChange(of: nameFocused) { _, focused in if !focused { saveName() } }
    }
}

/// A row of monochrome symbols. The first is "no icon of its own".
private struct IconPicker: View {
    let selected: String?
    let choose: (String?) -> Void

    private var choices: [(symbol: String, label: String, value: String?)] {
        [(AccountIcon.fallback, "None", nil)] + AccountIcon.choices.map { ($0.symbol, $0.label, Optional($0.symbol)) }
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 4), count: 9), spacing: 4) {
            ForEach(choices, id: \.symbol) { choice in
                let isSelected = choice.value == selected || (choice.value == nil && (selected ?? "").isEmpty)
                Button { choose(choice.value) } label: {
                    Image(systemName: choice.symbol)
                        .frame(width: 26, height: 24)
                        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(choice.label)
                .accessibilityLabel(choice.label)
            }
        }
    }
}

// MARK: - Sharing

private struct SharingPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                if model.sharingAccounts.isEmpty {
                    Text("Add a second account to share between accounts.").foregroundStyle(.secondary)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("Account")
                            ForEach(SharedThing.allCases, id: \.self) { thing in
                                Text(thing.shortTitle).help(thing.summary)
                            }
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(model.sharingAccounts, id: \.name) { profile in
                            GridRow {
                                Label(profile.displayName, systemImage: profile.iconSymbol)
                                    .lineLimit(1)
                                    .frame(minWidth: 120, alignment: .leading)
                                ForEach(SharedThing.allCases, id: \.self) { thing in
                                    SourcePicker(model: model, profile: profile, thing: thing).fixedSize()
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Share with another account")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Note("History: the two accounts use one set of Claude Code sessions. Connectors and extensions: copied from the account you pick. Default can be shared from, but is never changed.")
                    Note("Rules, skills, plugins and settings are always shared by every account. Conversations in Claude Desktop, and connectors such as Gmail or Slack, belong to one Claude account and cannot be shared.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// "Not shared", or one of the other accounts. Used in the table and on
/// each account's page.
private struct SourcePicker: View {
    @ObservedObject var model: SettingsModel
    let profile: Profile
    let thing: SharedThing

    var body: some View {
        Picker(thing.shortTitle, selection: Binding(
            get: { model.source(thing, for: profile)?.name ?? "" },
            set: { name in model.setSource(thing, for: profile, to: model.profiles.first { $0.name == name }) })) {
            Text("Not shared").tag("")
            Divider()
            ForEach(model.choices(thing, for: profile), id: \.name) { choice in
                Text(choice.displayName).tag(choice.name)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityLabel("\(thing.title) for \(profile.displayName)")
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) }))
                LabeledContent {
                    if model.commandLineToolInstalled {
                        Text("Installed").foregroundStyle(.secondary)
                    } else {
                        Button("Install") { model.installCommandLineTool() }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Command line tool")
                        Text("Use Switchboard from a terminal with cprof.").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                LabeledContent("Help") {
                    Button("Open Guide") { Actions.openGuide() }
                    Button("Show Log") { Actions.showLog() }
                }
                LabeledContent("Version", value: Actions.version)
            } footer: {
                Note("Switchboard is an independent tool, not made by Anthropic.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Small explanatory text under a section, aligned with the rows above it.
private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
