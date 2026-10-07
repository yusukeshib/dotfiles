# AGENTS.md

Guidance specific to the `~/dotfiles` repository. Follow the shared guidance in
`~/AGENTS.md` as well.

## Dotfiles workflow

This is a normal git repo at `~/dotfiles`. Tracked files live under
`~/dotfiles/home/<path>` and are symlinked to the matching `$HOME` path by
`~/dotfiles/bin/dots`; editing either path is live immediately. There is no
chezmoi or templating. Use normal git commands in `~/dotfiles`, and never use the
retired bare repo at `~/.dotfiles`.

Managed files use file-level symlinks so runtime and secret files are not exposed.

When changing a dotfile:

1. Edit its `$HOME` or `~/dotfiles/home` path directly.
2. For a new file, first create it under `$HOME`, then run
   `dots adopt ~/path/to/file` to move it into the repo and symlink it back.
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
| git | `~/.gitconfig`, `~/.config/git/gitconfig_darwin` |
| prompt / terminal | `~/.config/starship.toml`, `~/.config/tmux/tmux.conf`, `~/.config/ghostty/` |
| neovim | `~/.config/nvim/` |
| atuin / direnv | `~/.config/atuin/config.toml`, `~/.config/direnv/direnv.toml` |
| Homebrew | `~/Brewfile` |
| Shared agent skills | `~/.agents/skills/` |
| Codex CLI | `~/.codex/config.toml` |

## Configuration conventions

- Put all zsh aliases in `~/.config/zsh/init.zsh`, grouped by tool and gated with
  `if type "<cmd>" > /dev/null; then ...`. Use `~/.zshenv` only for environment
  variables required by non-interactive shells; tool-dependent PATH setup,
  completions, and plugins belong in `init.zsh`.
- Edit `~/.gitconfig` directly. Put macOS-only settings in
  `~/.config/git/gitconfig_darwin`; its trailing include in `~/.gitconfig` must
  remain last so platform overrides win.
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
