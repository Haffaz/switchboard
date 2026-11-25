# Troubleshooting

Start with the log. In the Switchboard menu choose **Help**, then **Show Log**. It records each step of a sign-in and each quit, with times. It never contains sign-in codes.

The log file is `~/Library/Logs/Switchboard.log`.

## Signing in

### The browser's "Open Claude" goes to the wrong window, or nothing happens

Start the sign-in from Switchboard, not from inside the Claude window: point at the account and choose **Sign In to Claude Desktop…**. Switchboard can only route the browser's link while it knows a sign-in is in progress.

If you did that and it still fails, check the two items below.

### macOS asked "Switchboard wants to control Claude" and I clicked Don't Allow

Open **System Settings → Privacy & Security → Automation**, find Switchboard, and turn on **Claude**. Then start the sign-in again.

If the sign-in is still waiting, Switchboard shows a dialog with **Open Settings** and **Try Again**. It holds the sign-in while you fix the setting.

### "(account) is still signing in. Finish or cancel that first."

Switchboard runs one sign-in at a time. Finish the first one, or wait: a sign-in that is never finished is abandoned after 10 minutes.

### "Claude for (account) was closed before the sign-in finished"

The account's Claude window was quit before the browser step ended. Start the sign-in again and leave the window open until it finishes.

### Links to Claude open in Switchboard, or do nothing

During a sign-in, Switchboard is briefly the app that opens `claude://` links. It gives them back when the sign-in ends, after 10 minutes, and when it quits.

If links still do not reach Claude, quit Switchboard and open it again. On every start it checks whether it still holds the links and gives them back.

## Accounts and status

### The menu says "Sign In to Claude Code…" but I just signed in

Switchboard asks Claude Code about its sign-in at most every 10 seconds. Close the menu, wait a moment, and open it again.

### A new account has no MCP servers

That is expected. Claude Code stores MCP servers added with `--scope user` together with the sign-in, so each account has its own. Add them again in the new account.

### An account ignores a change I made to my rules, agents or settings

The account may have its own copy of that item in place of the shared link. Run:

```bash
cprof link <name>
```

It restores missing links and lists items the account keeps as its own. To go back to the shared version of one, delete the account's copy in `~/.claude-profiles/<name>/cli` and run the command again.

## Opening and quitting

### I closed a Claude window but the green dot is still there

Closing a window does not quit the app. Point at the account and choose **Quit Claude Desktop**.

### "Claude (account) is still running"

Claude can refuse to quit while it is working, or it may be waiting for you to answer a question in its own window. Look at that window first. **Force Quit** stops it right away, and anything unsaved there is lost.

### Clicking an account does nothing

Use **Open Claude Desktop** in the account's side menu. If that also does nothing, check the log, and check that Claude Desktop is installed.

### "Claude Desktop is not installed"

Switchboard looks for Claude Desktop anywhere on your Mac. Install it from [claude.ai/download](https://claude.ai/download), open it once, and try again.

### "Claude Code is not installed", or a Terminal window says so

Install Claude Code from [claude.com/claude-code](https://claude.com/claude-code). Terminal windows opened by Switchboard run your normal shell setup first, so `claude` must work when you type it in a new Terminal window yourself.

## The app itself

### "Open at Login" shows an error

Switchboard must be in `/Applications` for this to work. Move it there, open it, and try again.

### `cprof` is "command not found"

Choose **Install Command Line Tool** in the menu. If it is still not found, add `~/.local/bin` to your `PATH`.

If the menu item is there even though you installed the tool before, the old link points to a previous version. Choosing it again repairs the link.

### The Dock or Finder shows an old icon

macOS caches app icons. Log out and back in to refresh it.

## Uninstalling

1. For each account you added, choose **Remove Account…** in its menu. This signs it out of Claude Code and deletes its data.
2. Quit Switchboard and delete `/Applications/Switchboard.app`. If you installed with Homebrew, run `brew uninstall --cask switchboard` instead.
3. Delete what is left:

```bash
rm -rf ~/.claude-profiles ~/.local/bin/cprof ~/Library/Logs/Switchboard.log
```

4. Delete any `Claude (name)` apps in `~/Applications`.
5. If you added the `eval "$(cprof init zsh)"` line to `~/.zshrc`, remove it.

Your Default account, in `~/.claude` and Claude Desktop's own data folder, is untouched by all of this.

## Still stuck?

Open an issue on GitHub. Include your macOS version, your Switchboard version (shown at the top of the **Help** window), and the relevant lines of the log.
