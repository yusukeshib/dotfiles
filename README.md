# dotfiles

A **normal git repo** (not a bare/`$HOME`-work-tree setup). Every tracked
dotfile lives under [`home/`](home/) (all platforms) or `home-<platform>/`
(only that platform, e.g. [`home-darwin/`](home-darwin/)) mirroring its real
`$HOME` path, and is **symlinked** into `$HOME` by the [`bin/dots`](bin/dots)
manager.

```
~/dotfiles/
├── home/            # symlinked into $HOME everywhere (home/.zshrc -> ~/.zshrc, …)
├── home-darwin/     # macOS only: LaunchAgents, 1Password Git signing
├── bin/
│   ├── dots         # symlink manager
│   └── brew-add / brew-remove / brew-sync   # Brewfile edits + convergence
├── tests/           # isolated regression checks
├── bootstrap.sh     # fresh-machine setup
└── README.md
```

## Fresh machine

```sh
git clone git@github.com:yusukeshib/dotfiles.git ~/dotfiles
~/dotfiles/bootstrap.sh          # symlinks everything into $HOME (backs up conflicts)
brew bundle --file=~/Brewfile    # install packages
~/.config/tmux/plugins/tpm/bin/install_plugins   # if bootstrap ran before tmux existed
exec zsh
```

## Daily use

Just edit files under `~/dotfiles/home/…` (or their symlinks in `$HOME` — same
file) and commit normally:

```sh
cd ~/dotfiles
git add -A && git commit -m "zsh: …" && git push
```

## Managing symlinks — `dots`

```sh
dots link [--dry-run]          # create/repair all symlinks (backs up conflicts to *.predots-*/original)
dots status                    # show every managed path: ok / drift / missing / stale / orphan
dots relink [path…]            # re-adopt a path a tool rewrote in place (drift)
dots adopt [--platform] <path> # start tracking a new regular $HOME file (moves it in + symlinks back)
dots unlink <path>             # detach a symlink back into a real copy
```

The platform is the lowercase `uname -s` (`darwin`, `linux`); set
`DOTS_PLATFORM` to override it. `adopt --platform` stores the file under
`home-<platform>/` instead of `home/`. A path may exist in only one tree. To move
a file between trees, `git mv` it and run `dots link`: links that still point into
the repository are replaced without a backup (`stale`), and links for paths now
managed only on other platforms are removed together with directories left empty
(`orphan`). launchd remembers the resolved path of a loaded LaunchAgent, so after
moving one, re-register it: `launchctl bootout gui/$UID/<label>` then
`launchctl bootstrap gui/$UID ~/Library/LaunchAgents/<label>.plist`.

Paths for `adopt`, `relink`, and `unlink` may be absolute under `$HOME` or
relative to `$HOME` (not the current directory). Directory adoption, `..`
traversal, symlinked parent directories, and adopting over an existing repository
file are rejected. `relink` and `unlink` only accept managed files; `unlink`
requires a healthy managed symlink. Restore a missing repository source before
relinking it.

Backups use unique `*.predots-XXXXXXXX/original` paths, including conflicting
symlinks, so repeated operations do not overwrite prior backups. On a reported
replacement failure, the manager attempts to restore the original live path.
If interrupted or restoration itself fails, keep the reported backup/staging
paths and recover their contents before retrying. Do not run mutating `dots`
commands concurrently; these are recoverable per-file operations, not a
transaction across the whole home directory.

## Drift (important)

Some tools (such as pi and Claude Code) rewrite their config via atomic rename, which
replaces a **file** symlink with a regular file. `dots status` flags these as
`drift`; run `dots relink` to pull the new content back into the repo, then
commit. Only tracked files are linked; runtime state remains untracked.

## Rex GUI preferences (macOS)

`~/Library/Preferences/com.superlogical.rex.plist` is symlinked directly to
`home-darwin/Library/Preferences/com.superlogical.rex.plist`. No export/apply
helper is needed. This tracks the entire plist, including custom themes,
session/activity state, and machine-specific preferences; review diffs before
committing. Rex's Lua `init.lua` configuration is separate.

macOS may replace the symlink when saving preferences. If `dots status` reports
`drift`, run `dots relink Library/Preferences/com.superlogical.rex.plist` before
committing. Quit Rex before restoring preferences on another Mac and reopen it
afterward; macOS preference caching may delay recognition of external changes.
The font `Paper Mono` must be installed separately.

## Pi packages

`settings.json` pins third-party packages to exact versions (bump them
deliberately after reviewing the release), while first-party
`@yusukeshib/*` packages track `0.x`.

## Trusted box workspaces

Repositories under `~/.box/workspaces/` are trusted automatically: direnv
whitelists the prefix (`direnv.toml`) and pi loads project resources everywhere
(`defaultProjectTrust: "always"`), so unattended agents and bots work in new
workspaces without prompts. The cost is that checking out a branch runs its
`.envrc` and project pi extensions without review. Only check out code you would
execute; inspect `.envrc` and `.pi/` of untrusted branches before entering them.

## Pi theme loading

`websafe` lives in `~/.pi/agent/theme-resources/` and is explicitly loaded by
`settings.json`. Keep it outside `~/.pi/agent/themes/`: Pi 1.1.0 repeatedly
recreates that directory's hot-reload watcher during startup, and closing the
macOS filesystem watcher can block input for seconds. The explicit resource
keeps the same colors without that watcher; use `/reload` after editing it.
When migrating an existing checkout, remove the old
`~/.pi/agent/themes/websafe.json` symlink if it still points into this repository.

## Local regression checks

These tests isolate HOME/Git state and mock external operations; they do not
load your shell/editor configuration or run Homebrew, Docker, or cloud jobs.

```sh
python3 -m unittest discover -s tests -v
DOTS_TEST_BASH="$(command -v bash)" python3 -m unittest discover -s tests -p test_dots.py -v
python3 tests/check_configs.py
```

The default manager tests use `/bin/bash` (Bash 3.2 on macOS). Shell helper tests
require `/bin/zsh`. JSON/TOML parsing requires Python 3.11+ when running the
separate config checker. Run the six mocked Cargo Expand cases with isolated
editor state:

```sh
(
  test_home=$(mktemp -d) || exit 1
  trap 'rm -rf "$test_home"' EXIT
  HOME="$test_home" XDG_CONFIG_HOME="$test_home/config" \
    XDG_DATA_HOME="$test_home/data" XDG_STATE_HOME="$test_home/state" \
    XDG_CACHE_HOME="$test_home/cache" \
    nvim --headless -u NONE -i NONE -l tests/test_cargo_expand.lua \
    "$PWD/home/.config/nvim/lua/plugins/cargo_expand.lua"
)
```

Passing mocked tests is not proof of Linux service or external integration health.
