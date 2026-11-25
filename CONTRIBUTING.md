# Contributing to Switchboard

Thanks for wanting to help. Bug reports, ideas, documentation fixes and code are all welcome.

## Ways to contribute

- **Report a bug.** Something broke, or behaved differently from what the guides say.
- **Suggest an idea.** A feature, or a change to how something works.
- **Improve the docs.** A step that confused you is worth fixing for the next person.
- **Send code.** A fix or a feature, as a pull request.

## Reporting a bug

Open an issue on GitHub and include:

1. What you did, step by step.
2. What you expected, and what happened.
3. Your macOS version and your Switchboard version. Rest the pointer on the menu bar icon to see the version.
4. The relevant lines of the log. Open the menu, hold **Option (⌥)** and choose **Show Log**. The log never contains sign-in codes or passwords, but read it before you paste it.

Please check [Troubleshooting](docs/troubleshooting.md) first. Your problem may already have a fix there.

## Suggesting an idea

Open an issue and describe the problem you want solved, not only the solution you have in mind. For anything larger than a small fix, please do this before you write code, so nobody builds something that will not be merged.

Switchboard aims to stay small. Some ideas will be declined for that reason alone.

## Reporting a security problem

Please do not open a public issue. Use GitHub's private vulnerability reporting on this repository, so the problem can be fixed before it is widely known.

## Sending a pull request

### Set up

You need macOS 14 or later and Xcode 16 or later.

```bash
git clone https://github.com/Haffaz/switchboard.git
```

```bash
cd switchboard && swift build && swift test
```

To try your build as a real app:

```bash
./build.sh --install
```

Tests run against temporary folders. They never touch your real Claude accounts.

### Make the change

1. Create a branch from `main`.
2. Keep the change to one thing. Two fixes are two pull requests.
3. Add or update tests for it.
4. If you changed the menu or a dialog, update the guides in `docs/` and regenerate the screenshots. [Development](docs/development.md#updating-the-screenshots) says how.

### What a change must respect

These are the project's fixed rules. A pull request that breaks one will not be merged.

- **No third-party libraries.** Switchboard sits next to people's logins. A codebase someone can read in an afternoon is part of what makes it trustworthy.
- **Never read, store or log secrets.** No tokens, no Keychain items, no contents of sign-in links.
- **Never change the Default account.** `~/.claude` and Claude Desktop's own data folder are read, never moved or rewritten.
- **Rules live in the core.** Decisions go in `SwitchboardCore`, with a test. The app and `cprof` stay thin.
- **Keep dialogs short.** One thing per dialog, and no pop-up when something simply worked.

### Before you open it

- `swift build` finishes with no warnings.
- `swift test` passes.
- The commit messages follow [Conventional Commits](https://www.conventionalcommits.org): `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.

In the pull request, say what changed, why, and how you checked it. If you could not test part of it, say which part.

## Finding your way around the code

[Development](docs/development.md) describes the project layout, where each kind of change belongs, and the tools for screenshots and releases.

## License

By contributing, you agree that your contribution is released under the project's [MIT license](LICENSE).
