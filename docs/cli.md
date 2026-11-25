# The `cprof` command

`cprof` does from a terminal what the menu does with clicks. It shares all of its logic with the app, so the two always agree.

## Install

If you installed Switchboard with Homebrew, `cprof` is already on your `PATH`.

Otherwise, in the Switchboard menu, choose **Install Command Line Tool**. That links `cprof` into `~/.local/bin`.

Or link it yourself:

```bash
ln -s "/Applications/Switchboard.app/Contents/MacOS/cprof" ~/.local/bin/cprof
```

If your shell cannot find `cprof` afterwards, add `~/.local/bin` to your `PATH`.

## Naming an account

Commands marked `[name]` work without a name. They then use the first of these that applies:

1. the `CPROF_PROFILE` environment variable,
2. the nearest `.claude-profile` file, in the current folder or any folder above it,
3. `default`.

Account names use lowercase letters, digits, `-` and `_`, start with a letter or digit, and are at most 32 characters. `default` is your original setup and always exists.

An account can also have a friendlier shown name, set with `cprof rename`. Commands always take the account name, not the shown name.

## Accounts

### `cprof list [--json]`

Lists accounts and the email Claude Code is signed in with. `*` marks the account the current folder uses. Running `cprof` with no command does the same.

```
$ cprof list
* default          you@personal.example
  work             you@company.example
  side-project     (not signed in)
```

`--json` prints the same accounts for scripts, with these fields: `name`, `label`, `email`, `icon`, `desktopRunning`, `desktopSignedIn`, `cliDir`, `desktopDir`.

### `cprof add <name>`

Creates an account: its folders, and links to your shared rules, agents, skills and settings.

```bash
cprof add work
```

You can type the name the way you want it shown. The account's own name is a tidied form of it:

```
$ cprof add My Work
Created my-work (shown as My Work).
```

### `cprof rm <name> [--yes]`

Signs the account out of Claude Code and deletes its folders. It asks first unless you pass `--yes`. Quit that account's Claude Desktop before removing it. `default` cannot be removed.

### `cprof rename <name> [label]`

Changes the name shown for an account in the menu and in `cprof list`. It works for `default` too. Leave the label out to go back to the original name.

```bash
cprof rename default Personal
```

Only the shown name changes. In commands you still use the original name (`default`, `work`), because folders and sign-ins are tied to it. `cprof list` shows both:

```
$ cprof list
* default (Personal)       you@personal.example
  work (Day job)           you@company.example
```

### `cprof icon <name> [symbol]`

Sets the icon shown next to the account in the menu. The symbol is the name of an Apple system symbol, such as `briefcase`, `house` or `building.2`. Leave the symbol out to clear the icon.

```bash
cprof icon work briefcase
```

## Opening Claude

### `cprof cli [name] [-- args]`

Runs `claude` as an account. Everything after `--` is passed to `claude`.

```bash
cprof cli work
```

```bash
cprof cli work -- --resume
```

### `cprof desktop [name]`

Opens Claude Desktop as an account. If that account's Claude is already running, its window comes to the front.

### `cprof code [name]`

Opens a new Terminal window running Claude Code as an account.

### `cprof login [name]`

Opens a new Terminal window that signs Claude Code in for an account.

### `cprof terminal [name]`

Opens a new Terminal window set to an account, at a shell prompt. Running `claude` there uses that account.

Terminal windows open in Terminal.app. To use another app that can open `.command` files, set `CPROF_TERMINAL_APP`:

```bash
export CPROF_TERMINAL_APP=iTerm
```

## Folders and shells

### `cprof use <name>`

Pins the current folder to an account by writing a `.claude-profile` file in it. Every folder inside it follows.

```bash
cd ~/Projects/client-site && cprof use work
```

### `cprof which`

Prints the account the current folder uses.

### `cprof init zsh|bash`

Prints a snippet that makes plain `claude` follow each folder's account. Add this line to `~/.zshrc` (or `~/.bashrc`):

```bash
eval "$(cprof init zsh)"
```

It defines two things:

- `claude` — runs Claude Code as the current folder's account.
- `cprof-use <name>` — switches the current shell to an account until you close it.

### `cprof env [name]`

Prints the shell lines that switch a shell to an account. `cprof-use` is the easy way to apply them. To do it by hand:

```bash
eval "$(cprof env work)"
```

## Maintenance

### `cprof link <name>`

Puts back any missing links from an account to your shared items in `~/.claude`. Files an account has replaced with its own copy are left alone and listed.

### `cprof app <name>`

Makes `~/Applications/Claude (<name>).app`, a small app that opens that account's Claude Desktop. Drag it to your Dock.

### `cprof install-cli`

Links `cprof` into `~/.local/bin`.

### `cprof help`

Prints a summary of every command.

## Environment variables

| Variable | What it does |
|---|---|
| `CPROF_PROFILE` | The account to use when a command does not name one. `cprof-use` sets it. |
| `CPROF_TERMINAL_APP` | The app that opens new Terminal windows. Defaults to Terminal. |
| `CPROF_HOME` | Where account folders live. Defaults to `~/.claude-profiles`. Set it everywhere or nowhere: the app reads it only if it is in the app's own environment. |

## Exit status

`cprof` exits with `0` on success and `1` on any error, with a message on standard error that starts with `cprof:`.
