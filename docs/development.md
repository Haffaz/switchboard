# Development

This guide is for people working on Switchboard's code. To report a bug or send a change, start with [Contributing](../CONTRIBUTING.md).

## Build and test

You need macOS 14 or later and Xcode 16 or later.

```bash
swift build
```

```bash
swift test
```

```bash
swift run cprof list
```

```bash
./build.sh
```

`./build.sh` makes `build/Switchboard.app`, signed for local use only. Add `--install` to copy it to `/Applications` and open it.

## Project layout

Everything is Swift, with no third-party libraries.

```
Sources/SwitchboardCore/      Every rule, once. No user interface.
  AccountStore.swift            accounts on disk, shared links, names, icons, which account a folder uses
  Sharing.swift                 optional sharing: history, connectors, Desktop extensions
  ClaudeDesktop.swift           finding, opening and quitting Claude Desktop copies
  ProcessArguments.swift        matching a running copy to its account
  LinkRouter.swift              where a claude:// link should go
  Launchers.swift               Terminal windows and Dock launchers
  Shell.swift                   running other programs, and asking Claude Code about its login
Sources/Switchboard/          The menu bar app.
  MenuController.swift          the menu bar menu: accounts, Settings, Quit
  SettingsView.swift            the Settings window: a sidebar of accounts and General, one page each
  SettingsModel.swift           what the Settings window shows, and the changes it asks for
  Actions.swift                 everything the app can do; the menu and Settings both call it
  DesktopSignIn.swift           the sign-in flow
  LinkRelay.swift               owning claude:// links during a sign-in
  Dialogs.swift                 every dialog, in one place
  Demo.swift                    sample data and screenshots for the docs
Sources/cprof/                The command-line tool.
tests/SwitchboardCoreTests/   Unit tests for the core.
tools/make-icon.swift         Draws the app icon.
packaging/                    The Homebrew recipe template and the app's entitlements.
docs/                         The guides.
```

[How it works](how-it-works.md) explains the design: how accounts are kept apart and how sign-in is routed.

## Where a change belongs

- **A rule or a decision** goes in `SwitchboardCore`, with a test. Examples: what a valid account name is, which items are shared, where a link is routed.
- **The app and `cprof` stay thin.** They read input, call the core, and show the result. If you are writing the same check in both, it belongs in the core.
- **Daily actions go in the menu; everything else in Settings.** Keep the menu short.
- **Wording shown to people** goes in `Dialogs.swift`, or in `CLI.swift` for `cprof`. Write it for someone who has never seen a terminal.
- **Anything that needs a running Claude** cannot be unit tested. Keep that code small and put the decisions around it in the core.

The code uses Swift 6 with strict concurrency, and the build has no warnings.

## Logging safely

Never log the contents of a `claude://` link: its path, query and fragment can each carry a sign-in code. Use `LinkRouter.logLabel`, which keeps only the scheme, the host and the kind of link. A test checks that no code can pass through it.

## Updating the screenshots

The pictures in `docs/images` are real captures of the app showing sample accounts. Regenerate them after any change to the menu or a dialog:

```bash
swift build && "$(swift build --show-bin-path)/Switchboard" --demo-screenshots docs/images
```

Menus and dialogs flash on screen for a few seconds while it captures them. It reads no real account and needs no Screen Recording permission. Run it from the project folder, so the dialogs can show the project's icon.

The sample accounts and the list of captures are in `Demo.swift`.

## Checking the sign-in relay

The part that holds `claude://` links during a sign-in cannot be unit tested, because it changes a system setting. There is a self-test instead:

```bash
open -a /Applications/Switchboard.app --args --relay-selftest
```

It holds the links for 12 seconds, takes them back if another app claims them in that time, then returns them and quits. The log shows each step. No account is touched.

## Changing the icon

The app icon and the menu bar icon are drawn by code: `tools/make-icon.swift` and `MenuItems.barIcon()`. Keep the two in step. `./build.sh` redraws the app icon when the script changes.

## Making a release

A release is a signed, notarized DMG on GitHub, plus a Homebrew recipe that points at it. Only maintainers make releases. It needs an Apple Developer ID.

One-time setup:

1. Copy `release.local.env.example` to `release.local.env` and fill in your identity. That file is ignored by git.
2. Store a notary password in your Keychain:

```bash
xcrun notarytool store-credentials switchboard-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

For each release:

1. Set `VERSION` in `release.env`, then get that change onto `main` on GitHub.
2. Build, sign and notarize the DMG:

```bash
./release.sh
```

3. See what publishing would do. This changes nothing and lists anything that is not ready:

```bash
./publish.sh --dry-run
```

4. Publish:

```bash
./publish.sh
```

`publish.sh` tags the release, creates the GitHub release with the DMG, and writes the Homebrew recipe to the tap repository named in `release.env`, creating that repository the first time. The recipe is generated from `packaging/switchboard.rb.template`; edit the template, never the copy in the tap.
