# dotfiles

A **normal git repo** (not a bare/`$HOME`-work-tree setup). Every tracked
dotfile lives under [`home/`](home/) mirroring its real `$HOME` path, and is
**symlinked** into `$HOME` by the [`bin/dots`](bin/dots) manager.

```
~/dotfiles/
├── home/            # everything symlinked into $HOME (home/.zshrc -> ~/.zshrc, …)
├── bin/dots         # symlink manager
├── bootstrap.sh     # fresh-machine setup
└── README.md
```

## Fresh machine

```sh
git clone git@github.com:yusukeshib/dotfiles.git ~/dotfiles
~/dotfiles/bootstrap.sh          # symlinks everything into $HOME (backs up conflicts)
brew bundle --file=~/Brewfile    # install packages
~/.tmux/plugins/tpm/bin/install_plugins
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
dots link [--dry-run]   # create/repair all symlinks (backs up conflicts to *.predots-*/original)
dots status             # show every managed path: ok / drift / missing
dots relink [path…]     # re-adopt a path a tool rewrote in place (drift)
dots adopt <path>       # start tracking a new regular $HOME file (moves it in + symlinks back)
dots unlink <path>      # detach a symlink back into a real copy
```

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
separate config checker. TypeScript checks reuse the installed pi loader; set
`PI_CLI` or `JITI_PATH` if pi is not discoverable on PATH. Run the six mocked
Cargo Expand cases with isolated editor state:

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
