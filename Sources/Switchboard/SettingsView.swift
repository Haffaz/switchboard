import AppKit
import SwiftUI
import SwitchboardCore

/// The Settings window: one place for everything that is rare or needs a
/// line of explanation. Opened with "Settings…" in the menu.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    static let size = NSSize(width: 700, height: 600)

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
        let host = NSHostingController(rootView: SettingsView(model: model))
        host.sizingOptions = []  // the window decides the size; the view fills it, title bar included
        let window = NSWindow(contentViewController: host)
        window.title = "Switchboard Settings"
        // The sidebar runs to the top of the window, as in System Settings,
        // so the title bar is drawn over the content and its title hidden.
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
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

/// One sidebar (the accounts, then General) and one page beside it. No
/// tabs and no boxed groups: rows sit on the window under small titles.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model).frame(width: 200)
            Divider()
            ScrollView {
                Group {
                    if model.tab == .general {
                        GeneralPage(model: model)
                    } else if let profile = model.selectedProfile {
                        AccountPage(model: model, profile: profile).id(profile.name)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, Layout.titleBar + 8)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }
}

private enum Layout {
    /// Room for the window's close and minimise buttons.
    static let titleBar: CGFloat = 36
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Accounts")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.bottom, 4)
            ForEach(model.profiles, id: \.name) { profile in
                let selected = model.tab == .accounts && model.selectedProfile?.name == profile.name
                SidebarRow(icon: profile.iconSymbol, title: profile.displayName, selected: selected) {
                    if profile.isDefault { MainTag(onAccent: selected) }
                    Spacer(minLength: 4)
                    if model.running.contains(profile.name) {
                        Circle().fill(.green).frame(width: 7, height: 7).help("Claude Desktop is running")
                    }
                } action: {
                    model.selected = profile.name
                    model.tab = .accounts
                }
            }
            SidebarRow(icon: "plus", title: "Add Account…", selected: false, dimmed: true) { Spacer(minLength: 0) } action: {
                model.tab = .accounts
                model.addAccount()
            }
            Spacer(minLength: 12)
            SidebarRow(icon: "gearshape", title: "General", selected: model.tab == .general) { Spacer(minLength: 0) } action: {
                model.tab = .general
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, Layout.titleBar + 6)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.045))
    }
}

private struct SidebarRow<Trailing: View>: View {
    let icon: String
    let title: String
    let selected: Bool
    var dimmed = false
    @ViewBuilder let trailing: Trailing
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 18)
                Text(title).lineLimit(1)
                trailing
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(dimmed ? .secondary : .primary))
            .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - An account's page

private struct AccountPage: View {
    @ObservedObject var model: SettingsModel
    let profile: Profile
    @State private var name = ""
    @State private var editing = false
    @FocusState private var nameFocused: Bool

    private func saveName() {
        guard name != profile.displayName else { return }
        model.rename(profile, to: name)
    }

    private var status: String {
        let running = model.running.contains(profile.name) ? "Claude Desktop is running" : "Claude Desktop is not running"
        return profile.isDefault ? "Main account · \(running)" : running
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: profile.iconSymbol)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.displayName).font(.title3.weight(.semibold)).lineLimit(1)
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button(editing ? "Done" : "Edit Name and Icon") {
                    if editing { saveName() }
                    editing.toggle()
                }
            }
            if profile.isDefault {
                Note("The Claude setup you had before Switchboard. Other accounts can share its conversations, connectors and extensions. It is never moved or changed.")
                    .padding(.top, 10)
            }
            if editing {
                RowGroup(title: "Name and icon") {
                    Row("Name") {
                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder).labelsHidden().frame(width: 220)
                            .focused($nameFocused)
                            .onSubmit { saveName() }
                    }
                    Divider()
                    Row("Icon") { IconPicker(selected: profile.icon) { model.setIcon(profile, to: $0) } }
                }
            }
            RowGroup(title: "Sign-in") {
                Row("Claude Desktop") {
                    if profile.isDefault {
                        Text("Your usual sign-in").foregroundStyle(.secondary)
                    } else {
                        Text(profile.desktopSignedIn ? "Signed in" : "Not signed in").foregroundStyle(.secondary)
                        Button(profile.desktopSignedIn ? "Sign In Again…" : "Sign In…") { model.signInDesktop(profile) }
                    }
                }
                Divider()
                Row("Claude Code") {
                    Text(profile.codeSignedIn ? profile.email : "Not signed in").foregroundStyle(.secondary).lineLimit(1)
                    Button(profile.codeSignedIn ? "Sign In Again…" : "Sign In…") { model.signInCode(profile) }
                }
            }
            if profile.isDefault {
                UsedBySection(model: model, profile: profile)
            } else {
                SharingSection(model: model, profile: profile)
            }
            Divider().padding(.top, 18)
            HStack(spacing: 16) {
                if !profile.isDefault { Button("Add Dock Icon") { model.makeDockApp(profile) } }
                Button("Open Terminal") { model.openTerminal(profile) }
                    .help("A Terminal window where claude and cprof use this account")
                Button("Show Files") { model.reveal(profile) }
                Spacer()
                if !profile.isDefault {
                    Button("Remove Account…") { model.remove(profile) }.foregroundStyle(.red)
                }
            }
            .buttonStyle(.link)
            .padding(.top, 12)
        }
        .onAppear { name = profile.displayName }
        // Leaving the field, or picking another account, saves the name too.
        .onDisappear { saveName() }
        .onChange(of: nameFocused) { _, focused in if !focused { saveName() } }
    }
}

/// A titled run of rows, with no box around it.
private struct RowGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .padding(.top, 22).padding(.bottom, 2)
            content
        }
    }
}

/// A label on the left, its value and controls on the right.
private struct Row<Trailing: View>: View {
    let label: String
    @ViewBuilder let trailing: Trailing

    init(_ label: String, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 8)
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

/// An account's one sharing choice: share with the default account, keep
/// separate, or choose thing by thing. Worded as what happens, not as
/// "same as", which read as if the whole account (sign-in too) were copied.
private struct SharingSection: View {
    @ObservedObject var model: SettingsModel
    let profile: Profile

    var body: some View {
        let main = model.defaultDisplayName
        let mode = model.sharingMode(profile)
        RowGroup(title: "Sharing") {
            ChoiceRow(title: "Share with \(main)",
                      detail: "Your main account's Claude Code conversations, connectors and extensions. Claude Desktop chats stay with each account.",
                      selected: mode == .same) { model.setSharingMode(profile, .same) }
            Divider()
            ChoiceRow(title: "Keep separate",
                      detail: "Its own conversations, connectors and extensions.",
                      selected: mode == .separate) { model.setSharingMode(profile, .separate) }
            Divider()
            ChoiceRow(title: "Choose for each",
                      detail: "Pick an account for conversations, connectors and extensions.",
                      selected: mode == .custom) { model.setSharingMode(profile, .custom) }
            if mode == .custom {
                ForEach(SharedThing.allCases, id: \.self) { thing in
                    Divider().padding(.leading, ChoiceRow.indent)
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.name(thing))
                            Text(Self.how(thing)).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        SourcePicker(model: model, profile: profile, thing: thing).frame(width: 150)
                    }
                    .padding(.vertical, 6)
                    .padding(.leading, ChoiceRow.indent)
                }
            }
        }
    }

    static func name(_ thing: SharedThing) -> String {
        switch thing {
        case .history: "Claude Code conversations"
        case .connectors: "Claude Code connectors"
        case .extensions: "Claude Desktop extensions"
        }
    }

    static func how(_ thing: SharedThing) -> String {
        switch thing {
        case .history: "Also in Desktop's Code tab (beta)"
        case .connectors: "MCP servers, copied in"
        case .extensions: "Copied in when it opens"
        }
    }
}

/// A radio button with a line of explanation under its title. The whole
/// row can be clicked.
private struct ChoiceRow: View {
    static let indent: CGFloat = 26
    let title: String
    let detail: String
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: ChoiceRow.indent - 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// On the default account's page: which accounts take what from it.
private struct UsedBySection: View {
    @ObservedObject var model: SettingsModel
    let profile: Profile

    var body: some View {
        let shared = model.sharesFrom(profile)
        RowGroup(title: "Shared with other accounts") {
            if shared.isEmpty {
                Text("No other account uses this one's conversations, connectors or extensions.")
                    .foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                ForEach(Array(shared.enumerated()), id: \.element.thing) { index, entry in
                    if index > 0 { Divider() }
                    Row(SharingSection.name(entry.thing)) {
                        Text(entry.accounts.map(\.displayName).joined(separator: ", ")).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// "Not shared", or one of the other accounts.
private struct SourcePicker: View {
    @ObservedObject var model: SettingsModel
    let profile: Profile
    let thing: SharedThing

    var body: some View {
        Picker(thing.shortTitle, selection: Binding(
            get: { model.source(thing, for: profile)?.name ?? "" },
            set: { name in model.setSource(thing, for: profile, to: model.profiles.first { $0.name == name }) })) {
            Text("Its own").tag("")
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

private struct GeneralPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("General").font(.title3.weight(.semibold))
            RowGroup(title: "Switchboard") {
                Row("Open at login") {
                    Toggle("Open at login", isOn: Binding(get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Command line tool")
                        Text("Use Switchboard from a terminal with cprof.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    if model.commandLineToolInstalled {
                        Text("Installed").foregroundStyle(.secondary)
                    } else {
                        Button("Install") { model.installCommandLineTool() }
                    }
                }
                .padding(.vertical, 8)
            }
            RowGroup(title: "About") {
                Row("Help") {
                    Button("Open Guide") { Actions.openGuide() }
                    Button("Show Log") { Actions.showLog() }
                }
                Divider()
                Row("Version") { Text(Actions.version).foregroundStyle(.secondary) }
            }
            Note("Switchboard is an independent tool, not made by Anthropic.").padding(.top, 14)
        }
    }
}

/// Marks the main account (the one Switchboard calls "default") in the list.
private struct MainTag: View {
    /// True on the selected sidebar row, where the text is white.
    var onAccent = false

    var body: some View {
        Text("Main")
            .font(.caption.weight(.medium))
            .foregroundStyle(onAccent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(onAccent ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(.quaternary), in: Capsule())
            .help("Your main account: the Claude setup you had before Switchboard")
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
