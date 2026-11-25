# Contributing

Thanks for wanting to help. Switchboard is a small project: about 2,000 lines of Swift and no third-party libraries. Most changes are quick to make and test.

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

Tests run against temporary folders. They never touch your real Claude accounts.

## Project layout

```
Sources/SwitchboardCore/      Every rule, once. No user interface.
  AccountStore.swift            accounts on disk, shared links, icons, which account a folder uses
  ClaudeDesktop.swift           finding, opening and quitting Claude Desktop copies
  ProcessArguments.swift        matching a running copy to its account
  LinkRouter.swift              where a claude:// link should go
  Launchers.swift               Terminal windows and Dock launchers
  Shell.swift                   running other programs, and asking Claude Code about its login
Sources/Switchboard/          The menu bar app.
  MenuController.swift          the menu and its actions
  DesktopSignIn.swift           the sign-in flow
  LinkRelay.swift               owning claude:// links during a sign-in
  Dialogs.swift                 every dialog, in one place
  HotKeys.swift                 the system-wide keyboard shortcuts
  Demo.swift                    sample data and screenshots for the docs
Sources/cprof/                The command-line tool.
tests/SwitchboardCoreTests/   Unit tests for the core.
tools/make-icon.swift         Draws the app icon.
docs/                         The guides.
```

## Where a change belongs

- **A rule or a decision** goes in `SwitchboardCore`, with a test. Examples: what a valid account name is, which items are shared, where a link is routed.
- **The app and `cprof` stay thin.** They read input, call the core, and show the result. If you are writing the same check in both, it belongs in the core.
- **Wording shown to people** goes in `Dialogs.swift`, or in `CLI.swift` for `cprof`. Write it for someone who has never seen a terminal.
- **Keep dialogs short.** One thing per dialog, in as few words as it takes, and no pop-up at all when something simply worked. Explanations belong in `docs/`.

## Guidelines

- **No third-party libraries.** Switchboard sits next to people's logins. A codebase someone can read in an afternoon is part of what makes it trustworthy.
- **Never read, store or log secrets.** No tokens, no Keychain items, no contents of sign-in links. `LinkRouter.logLabel` exists so that a link can be logged safely; there is a test for it.
- **Never change the Default account.** `~/.claude` and Claude Desktop's own data folder are read, never moved or rewritten.
- **Swift 6 with strict concurrency.** The build has no warnings; please keep it that way.
- **Test what you can.** Anything that needs a running Claude cannot be unit tested, so keep that code small and put the decisions around it in the core.

## Updating the screenshots

The pictures in `docs/images` are real captures of the app showing sample accounts. Regenerate them after any change to the menu or a dialog:

```bash
swift build && "$(swift build --show-bin-path)/Switchboard" --demo-screenshots docs/images
```

Menus and dialogs flash on screen for a few seconds while it captures them. It reads no real account and needs no Screen Recording permission. Run it from the project folder, so the dialogs can show the project's icon.

## Checking the sign-in relay

The part that holds `claude://` links during a sign-in cannot be unit tested, because it changes a system setting. There is a self-test instead:

```bash
open -a /Applications/Switchboard.app --args --relay-selftest
```

It holds the links for 12 seconds, takes them back if another app claims them in that time, then returns them and quits. The log shows each step. No account is touched.

## Changing the icon

The app icon and the menu bar icon are drawn by code: `tools/make-icon.swift` and `MenuItems.barIcon()`. Keep the two in step. `./build.sh` redraws the app icon when the script changes.

## Sending a change

1. Create a branch.
2. Make the change, with tests where they apply.
3. Run `swift build` and `swift test`. Both must be clean.
4. If the menu or a dialog changed, update the screenshots and the guides in `docs/`.
5. Open a pull request that says what changed and how you checked it.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org): `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.

## Making a release

A release is a signed, notarized DMG on GitHub, plus a Homebrew recipe that points at it. Signing needs an Apple Developer ID. You do not need one to contribute.

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

## Reporting a security problem

Please do not open a public issue for a security problem. Use GitHub's private vulnerability reporting on this repository, so it can be fixed before it is widely known.
