<p align="center"><img src="design/icon-1024.png" width="128" alt="Switchboard icon"></p>

# Switchboard

Run several Claude accounts on one Mac, side by side. Switchboard is a menu bar app for Claude Desktop and Claude Code, with a matching command line tool, `cprof`.

Switchboard is an independent project. It is not made by or affiliated with Anthropic.

## Install

Requires macOS 14 or later and Xcode's command line tools.

```bash
./build.sh --install
```

This builds **Switchboard.app**, copies it to `/Applications` and opens it. Its icon appears in the menu bar.

## Use

```
● [icon] Default               ▸      you@company.com
  [icon] work                  ▸      ─────────────
  [icon] side-project  Sign In ▸      Open Claude Desktop      ⌘2
─────────────                         Open Claude Code        ⇧⌘2
Add Account…              ⌘N          Open Terminal
Quit All Claude Desktops              ─────────────
─────────────                         Quit Claude Desktop
Open at Login                         ─────────────
Help                                  Icon ▸
Quit Switchboard          ⌘Q          Sign In to Claude Desktop Again…
                                      Add Dock Icon
                                      Show Files in Finder
                                      ─────────────
                                      Remove Account…
```

- **One row per account.** Point at it for everything that account can do. Clicking the row opens its Claude Desktop.
- A **green dot** means that account's Claude Desktop is running. Closing a Claude window leaves it running, like any Mac app; choose **Quit Claude Desktop** to stop it.
- A **Sign In** badge means Claude Desktop is not signed in for that account yet. Claude Desktop and Claude Code sign in separately.
- **⌘1, ⌘2…** open Claude Desktop and **⇧⌘1, ⇧⌘2…** open Claude Code while the menu is open.
- Give each account its own **Icon**, so you can find it by shape.
- **Default** is the setup you already had. Switchboard never moves or changes it.

## What is shared, what is separate

| Shared by every account (links to `~/.claude`) | Separate per account |
|---|---|
| CLAUDE.md, AGENTS.md, rules, agents, commands, skills, hooks, output styles, plugins, settings.json, keybindings | Sign-in, chat history, projects, MCP servers added with `--scope user`, Claude Desktop data |

A shared item is a link. If you replace one with a real file inside an account's folder, that account keeps its own copy. `cprof link <name>` restores missing links.

## How it works

| Part | How accounts stay separate | Where |
|---|---|---|
| Claude Code | The `CLAUDE_CONFIG_DIR` setting. Claude Code keeps a separate Keychain login per config folder. | `~/.claude-profiles/<name>/cli` |
| Claude Desktop | A separate copy of the app started with `--user-data-dir`. | `~/.claude-profiles/<name>/desktop` |

Two pieces do the work:

- **The core** (`Sources/SwitchboardCore`) holds every rule once: account folders, shared links, telling Claude copies apart, and where a sign-in link goes. It has no user interface and is unit tested.
- **The app** (`Sources/Switchboard`) is the menu and the sign-in flow on top of the core.
- **`cprof`** (`Sources/cprof`) is a small command-line program on top of the same core.

It is all Swift, with no third-party libraries.

### Sign-in and `claude://` links

A browser finishes a Claude Desktop sign-in by opening a `claude://` link. macOS gives that link to whichever Claude copy it chooses, which is usually the wrong one. So for the length of one sign-in, Switchboard:

1. becomes the app that opens `claude://` links,
2. passes the sign-in link to the account that asked for it, and every other link to the default Claude,
3. gives `claude://` back to the app that had it.

It gives the links back after the sign-in, after 10 minutes, when it quits, or the next time it starts if it crashed. macOS asks once for permission for Switchboard to control Claude; that is how the link is passed to one specific copy.

## Command line

Use **Switchboard ▸ Install Command Line Tool**, or link it yourself:

```bash
ln -s "/Applications/Switchboard.app/Contents/MacOS/cprof" ~/.local/bin/cprof
```

```bash
cprof                         # list accounts
cprof add work                # new account
cprof login work              # sign Claude Code in
cprof desktop work            # open Claude Desktop as "work"
cprof cli work -- --resume    # run claude with any arguments
cprof use work                # pin the current folder to "work"
cprof icon work briefcase     # menu icon (any macOS system symbol name)
```

To make plain `claude` follow each folder's account, add this to `~/.zshrc`:

```bash
eval "$(cprof init zsh)"
```

Which account a command uses: a name you type, then `$CPROF_PROFILE`, then the nearest `.claude-profile` file, then `default`.

## Security notes

- **Sign-in codes are never stored or logged.** The log (`~/Library/Logs/Switchboard.log`) records only that a link arrived and where it went.
- **Switchboard reads no tokens.** "Signed in" comes from the account ID and email that Claude writes to its own settings files.
- **A `.claude-profile` file picks the account for a folder**, and a cloned repository can contain one. It can only name an account you created, and `cprof` prints a notice when a folder's file chooses the account.
- **The app is not sandboxed.** It has to start Claude and write to `~/.claude-profiles`.

## Good to know

- Terminal windows open in Terminal.app. Set `CPROF_TERMINAL_APP` to another app that opens `.command` files.
- Keep the app in `/Applications`. Dock icons and the command line link point into it.

## Development

```bash
swift build          # compile the app and cprof
swift test           # unit tests (Swift Testing), run against temporary folders
swift run cprof list # try the command-line tool without installing
./build.sh           # build/Switchboard.app, ad-hoc signed
```

Layout:

```
Sources/SwitchboardCore/      shared logic: accounts, launchers, process matching, link routing
Sources/Switchboard/          the menu bar app
Sources/cprof/                the command-line tool
tests/SwitchboardCoreTests/   unit tests for the core
tools/make-icon.swift         draws the app icon
```

### Signed and notarized builds

1. Copy `release.local.env.example` to `release.local.env` and fill in your Developer ID. That file is gitignored.
2. Store a notary password once: `xcrun notarytool store-credentials switchboard-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID`
3. Run `./release.sh`. It tests, builds for Apple silicon and Intel, signs, notarizes, staples, and produces `build/Switchboard-<version>.dmg`.

## License

MIT. See [LICENSE](LICENSE).
