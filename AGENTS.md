# AGENTS.md

Guidance specific to the `~/dotfiles` repository. Follow the shared guidance in
`~/AGENTS.md` as well.

## Dotfiles workflow

This is a normal git repo at `~/dotfiles`. Tracked files live under
`~/dotfiles/home/<path>` (all platforms) or `~/dotfiles/home-<platform>/<path>`
(`darwin`, `linux`; that platform only) and are symlinked to the matching
`$HOME` path by `~/dotfiles/bin/dots`; editing either path is live immediately. There is no
chezmoi or templating. Use normal git commands in `~/dotfiles`, and never use the
retired bare repo at `~/.dotfiles`.

Managed files use file-level symlinks so runtime and secret files are not exposed.

When changing a dotfile:

1. Edit its `$HOME` or repository path directly.
2. For a new file, first create it under `$HOME`, then run
   `dots adopt ~/path/to/file` (add `--platform` for a file that must exist only
   on the current platform) to move it into the repo and symlink it back.
   Platform-specific files such as LaunchAgents belong in `home-<platform>/`.
3. Inspect the targeted diff, then stage, commit, and push from `~/dotfiles`.
   Commit messages use `<scope>: <what>` (for example, `zsh: add foo alias`).

Useful checks:

```sh
cd ~/dotfiles
git status --short --branch
git diff -- home/.zshrc
git ls-files | rg <pattern>
dots status
```

Some tools rewrite configs by atomic rename, replacing a file symlink with a
regular file. If `dots status` reports `drift`, run `dots relink` to pull the
live content into the repo before committing.

## Key paths

All paths below are real `$HOME` paths:

| What | Path |
| --- | --- |
| zsh entry | `~/.zshenv`, `~/.zshrc` |
| zsh init / aliases / env | `~/.config/zsh/init.zsh` |
| zsh plugins / helpers | `~/.config/zsh/plugins.zsh`, `~/.config/zsh/utils.zsh` |
| git | `~/.gitconfig`, `~/.config/git/gitconfig_darwin` (macOS only) |
| prompt (native zsh + gitstatus) | `~/.config/zsh/prompt.zsh` |
| terminal | `~/.config/tmux/tmux.conf`, `~/.config/ghostty/` |
| neovim | `~/.config/nvim/` |
| atuin / direnv | `~/.config/atuin/config.toml`, `~/.config/direnv/direnv.toml` |
| Homebrew | `~/Brewfile` |
| Shared agent skills | `~/.agents/skills/` |
| pi agent | `~/.pi/agent/settings.json`, `lsp.json`, `AGENTS.md` |
| macOS LaunchAgents | `~/Library/LaunchAgents/` (macOS only) |

`~/.codex/` is intentionally untracked (`.gitignore`). Machine-local environment
and secrets go in the untracked `~/.config/zsh/local.zsh` (sourced by `init.zsh`);
do not put them in `~/.envrc`, which would make direnv run on every prompt.

Keep the per-prompt path free of external commands: Homebrew binaries can take
200-300ms to start after a few idle seconds on the work Mac (endpoint security).

## Configuration conventions

- Put all zsh aliases in `~/.config/zsh/init.zsh`, grouped by tool and gated with
  `if type "<cmd>" > /dev/null; then ...`. Use `~/.zshenv` only for environment
  variables required by non-interactive shells; tool-dependent PATH setup,
  completions, and plugins belong in `init.zsh`.
- Edit `~/.gitconfig` directly. Put macOS-only settings in
  `~/.config/git/gitconfig_darwin` (tracked in `home-darwin/`); its trailing
  include in `~/.gitconfig` must remain last so platform overrides win.
- Git must stay fully non-interactive (`core.editor = true`, `core.pager = cat`,
  `credential.interactive = false`). Do not add config or aliases that open an
  editor, pager, or prompt (`--interactive`, `--patch`, commit/tag without a
  message).
- Track desired packages in the shared `~/Brewfile`. Guard platform-specific
  entries with `if OS.mac?` or `if OS.linux?`. Edit the file, then when requested
  converge and verify with:
  ```sh
  brew bundle --file=~/Brewfile
  brew bundle check --file=~/Brewfile
  ```
  Do not use Nix or nixy. If Homebrew lacks a package, document its installation
  method in `~/Brewfile`.
- Shared agent skills live at `~/.agents/skills/<name>/SKILL.md`.
