# How it works

Switchboard does not change Claude. It starts Claude's own apps in a way that gives each account its own storage, and then keeps track of which copy belongs to which account.

## Two apps, two kinds of separation

| | How an account is kept separate | Where its data lives |
|---|---|---|
| **Claude Code** | The `CLAUDE_CONFIG_DIR` setting tells Claude Code which folder to use. Claude Code keeps a separate Keychain login for each folder. | `~/.claude-profiles/<name>/cli` |
| **Claude Desktop** | A separate copy of the app is started with its own data folder (the `--user-data-dir` option). | `~/.claude-profiles/<name>/desktop` |

Each account has a fixed name, which its folders are named after, and an optional shown name that you can change at any time in **Settings → Accounts**. Renaming never moves anything.

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

## Optional sharing

Beyond the items above, an account can share three more things with another account. You choose, for each account and each thing, which account it shares with.

Each account's page in **Settings → Accounts** has one **Sharing** choice:

- **Share with Default** (shown with your Default account's name): shares all three with the Default account. New accounts start here.
- **Keep separate:** shares none of the three.
- **Choose for each:** pick an account for each of the three.

From the terminal, use `cprof share`, or create an account with `cprof add <name> --separate`.

### Does it stay in sync?

Only history. The two accounts use the same files, so a session changed in one is changed in the other at once. Connectors and extensions are copies, made one way, from the account you picked: something added there arrives later, and something added in the receiving account stays there.

| Thing | When Client takes it from Work | How |
|---|---|---|
| **Claude Code History** | Client and Work use one set of sessions. `claude --resume` in either lists both accounts' sessions, with per-project memory and the saved file versions used to rewind. | Client's history folders become links to Work's. |
| **Claude Code Connectors** | Work's MCP servers (those added with `claude mcp add --scope user`) are copied into Client. | Copied into Client's settings file, every time you open the menu or Settings. |
| **Desktop Extensions** | Work's Claude Desktop extensions and local MCP servers are copied into Client's Claude Desktop. | Copied each time Client's Claude Desktop starts, never while it runs. |

Rules that keep this safe:

- **Default is only ever a source.** Other accounts can share from it, but Switchboard never writes to the setup you had before. Default's own choices are not shown.
- **History can chain but never loop.** If Client shares history with Work and Work with Default, all three use Default's sessions. Switchboard refuses a choice that would go round in a circle.
- **Sessions are moved, never overwritten.** When an account starts sharing history, its existing sessions are moved into the shared folder. If the same file exists in both places, the account's copy is kept aside in a folder ending `.before-sharing`.
- **Copies keep what the account added.** An account keeps any connector it added itself; on a name clash, the source's version wins. An extension installed only in the account is replaced the next time its Claude Desktop starts.
- **A copied connector may still ask you to sign in.** The list of servers is copied; each account's login to a server is not.
- **An account that holds others' history cannot be removed** until they stop sharing it, because their sessions live in its folder.
- **Stopping** removes the link or stops the copying. What was already copied stays. Shared sessions stay where they were, and the account that stopped starts with a fresh history.

Think before sharing history with an employer's account: its sessions become readable from the other account, and the other way round.

### What can never be shared

Conversations in Claude Desktop, and connectors such as Gmail or Slack that you add in Claude's settings, are stored by Anthropic under one account. They are not on your Mac, so Switchboard cannot share them.

## Telling Claude copies apart

Every running copy of Claude Desktop looks the same to macOS: same name, same icon, same app. Switchboard tells them apart by reading each copy's launch arguments, which include the data folder it was started with. A copy with no data folder argument is the Default account.

That is how the menu knows which accounts are running, and how "open", "bring to front" and "quit" reach the right copy.

## Signing in to Claude Desktop

Signing in happens in your browser. When you finish, the browser hands the result back to Claude by opening a `claude://` link.

With one Claude running, that works. With several, macOS gives the link to whichever copy it prefers, usually the first one started. That copy did not ask for a sign-in, so it ignores the link, and the window that did ask waits forever.

Switchboard fixes this for the length of one sign-in. It becomes the app that opens `claude://` links, and that changes what Claude does:

```
1. You choose Sign In for "work". Its Claude window opens.
2. Switchboard becomes the app that opens claude:// links.
3. You click to sign in. Claude sees it is no longer the claude:// app,
   so it signs in through its own sign-in sheet, which needs no link.
4. Claude saves the sign-in. Switchboard notices and gives claude://
   links back to the app that had them.
```

If Claude uses your browser anyway, the browser's "Open Claude" link arrives at Switchboard, which passes it to the "work" Claude.

Details that matter:

- **Every Claude that starts claims `claude://` links again.** So Switchboard takes the links only after the account's Claude has started, and for the rest of the sign-in it checks once a second and takes them back if another Claude claimed them.
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
| `~/.claude-profiles/.sharing.json` | Which account shares what with which |
| `~/.claude-profiles/.default-icon`, `.default-label` | The Default account's icon and shown name, if you set them |
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
- **MCP servers are per account unless you share them.** Claude Code stores them with the sign-in, so they are copied, not linked. See [Optional sharing](#optional-sharing).
- **Sign-in status can lag by a few seconds.** Switchboard asks Claude Code at most every 10 seconds.
