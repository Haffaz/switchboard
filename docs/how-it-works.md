# How it works

Switchboard does not change Claude. It starts Claude's own apps in a way that gives each account its own storage, and then keeps track of which copy belongs to which account.

## Two apps, two kinds of separation

| | How an account is kept separate | Where its data lives |
|---|---|---|
| **Claude Code** | The `CLAUDE_CONFIG_DIR` setting tells Claude Code which folder to use. Claude Code keeps a separate Keychain login for each folder. | `~/.claude-profiles/<name>/cli` |
| **Claude Desktop** | A separate copy of the app is started with its own data folder (the `--user-data-dir` option). | `~/.claude-profiles/<name>/desktop` |

The **Default** account is your existing setup: `~/.claude` for Claude Code, and Claude Desktop's normal data folder. Switchboard starts it the ordinary way and never moves or changes it.

Both mechanisms belong to Claude's apps, not to Switchboard. If a future Claude update changes either one, Switchboard will need an update too.

## What is shared and what is separate

When you add an account, Switchboard creates its Claude Code folder and fills it with links back to your default folder.

| Shared by every account | Separate for each account |
|---|---|
| `CLAUDE.md`, `AGENTS.md` | Sign-in |
| `rules`, `agents`, `commands`, `skills`, `hooks` | Chat history and projects |
| `output-styles`, `plugins` | MCP servers added with `--scope user` |
| `settings.json`, `keybindings.json` | All Claude Desktop data |

A shared item is a link, not a copy, so a change in `~/.claude` reaches every account at once.

If you want one account to differ, replace its link with a real file inside `~/.claude-profiles/<name>/cli`. Switchboard leaves real files alone. To put missing links back, run `cprof link <name>`.

## Telling Claude copies apart

Every running copy of Claude Desktop looks the same to macOS: same name, same icon, same app. Switchboard tells them apart by reading each copy's launch arguments, which include the data folder it was started with. A copy with no data folder argument is the Default account.

That is how the menu knows which accounts are running, and how "open", "bring to front" and "quit" reach the right copy.

## Signing in to Claude Desktop

Signing in happens in your browser. When you finish, the browser hands the result back to Claude by opening a `claude://` link.

With one Claude running, that works. With several, macOS gives the link to whichever copy it prefers, usually the first one started. That copy did not ask for a sign-in, so it ignores the link, and the window that did ask waits forever.

Switchboard fixes this for the length of one sign-in:

```
1. You choose Sign In for "work".
2. Switchboard becomes the app that opens claude:// links.
3. You sign in in the browser and click "Open Claude".
4. The link arrives at Switchboard, which passes it to the "work" Claude.
5. Switchboard gives claude:// links back to the app that had them.
```

Details that matter:

- **Only the sign-in link is redirected.** Any other `claude://` link that arrives meanwhile goes to the Default Claude, as it would without Switchboard.
- **One sign-in at a time.** A second sign-in would make it impossible to know whose link arrived, so Switchboard asks you to finish the first.
- **A sign-in link goes to the account that asked, or nowhere.** If that account's Claude was closed in the meantime, Switchboard drops the link and tells you to start again.
- **Links are always given back**: after the sign-in, after 10 minutes, when Switchboard quits, or the next time it starts if it crashed.

### Why macOS asks for permission

To pass the link to one specific copy of Claude, Switchboard sends it an "open this link" message, the same message macOS sends when you click a link. Sending a message to another app needs your permission, so macOS asks once: *"Switchboard wants to control Claude."*

Switchboard uses that permission for two things only: passing a sign-in link, and asking a running Claude to show its window again after you closed it.

## What Switchboard reads

Switchboard never reads tokens, passwords or Keychain items.

| To show… | Switchboard… |
|---|---|
| Whether Claude Code is signed in, and as whom | runs `claude auth status`, which answers yes or no and the email |
| Whether Claude Desktop is signed in | checks that Claude's own `config.json` contains an account ID |
| Which accounts are running | reads the launch arguments of running Claude copies |
| An account's icon | reads a one-line text file it wrote itself |

Sign-in links pass through Switchboard's memory on their way to Claude. They are never written to disk. The log file records only that a link arrived and where it went, never its contents.

## Which account a command uses

When you run `cprof` or the `claude` wrapper without naming an account, the first of these that applies wins:

1. A name you typed on the command line.
2. The `CPROF_PROFILE` environment variable.
3. The nearest `.claude-profile` file, looking in the current folder and then each folder above it.
4. `default`.

A `.claude-profile` file is one line of text: an account name. `cprof use <name>` writes it for you.

A cloned repository can contain one of these files. It can only name an account you created yourself, and `cprof` prints a notice whenever a folder's file picks the account.

## Files Switchboard creates

| Path | What it is |
|---|---|
| `~/.claude-profiles/<name>/` | One folder per account, readable only by you |
| `~/.claude-profiles/.launch/` | Small scripts that Terminal windows run |
| `~/.claude-profiles/.default-icon` | The Default account's icon, if you set one |
| `~/Applications/Claude (<name>).app` | Dock launchers, if you make them |
| `~/.local/bin/cprof` | A link to the command-line tool, if you install it |
| `~/Library/Logs/Switchboard.log` | The log |

## How the code is organised

Everything is Swift, with no third-party libraries.

```
Sources/SwitchboardCore/   Every rule, once: accounts on disk, shared links, telling
                           Claude copies apart, where a sign-in link goes. No user
                           interface. Unit tested.
Sources/Switchboard/       The menu bar app: the menu, dialogs and the sign-in flow.
Sources/cprof/             The command-line tool.
```

The app and `cprof` are thin layers over the same core, so they cannot disagree about what an account is or where it lives.

## Limits

- **Mac only.** It depends on how macOS launches and identifies apps.
- **Not sandboxed.** It has to start Claude and manage folders in your home folder.
- **MCP servers are per account.** Claude Code stores them with the sign-in, so they are not shared.
- **Sign-in status can lag by a few seconds.** Switchboard asks Claude Code at most every 10 seconds.
