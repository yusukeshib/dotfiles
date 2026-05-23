# AGENTS.md

Guidance for coding agents (Claude Code, Codex, pi, …) working in this repo.
**Read this before making any change.**

## TL;DR workflow

When the user asks to change a dotfile:

1. **Identify the target file** (e.g. `~/.zshrc`) and find its source here using
   the naming conventions below — *never edit the target in `$HOME` directly*.
2. **Edit the source file** in this repo (`$(chezmoi source-path)` =
   `~/.local/share/chezmoi`).
3. **Apply** with `chezmoi apply <target>` (or `chezmoi diff` first to preview).
   - If `chezmoi` complains "has changed since chezmoi last wrote it", confirm
     it's expected and use `chezmoi apply --force <target>` for that file only.
4. **Commit & push** from the source dir:
   ```sh
   cd "$(chezmoi source-path)"
   git add -A && git commit -m "<scope>: <what>" && git push
   ```

## Source ⇄ target mapping (chezmoi naming)

| Source prefix / suffix     | Target                                      |
| -------------------------- | ------------------------------------------- |
| `dot_foo`                  | `~/.foo`                                    |
| `private_dot_foo`          | `~/.foo` with mode `0600` (private)         |
| `private_foo`              | `~/foo` with mode `0600`                    |
| `*.tmpl`                   | Rendered as a Go template (uses `.chezmoi.*`) |
| Directory `private_dot_config` | `~/.config` (private)                   |

So:
- `dot_zshrc`                                 → `~/.zshrc`
- `dot_gitconfig.tmpl`                        → `~/.gitconfig` (templated)
- `private_dot_config/zsh/init.zsh`           → `~/.config/zsh/init.zsh`
- `private_dot_config/nixy/nixy.json`         → `~/.config/nixy/nixy.json`
- `dot_claude/skills/.../SKILL.md`            → `~/.claude/skills/.../SKILL.md`

To resolve a target → source quickly: `chezmoi source-path ~/.zshrc`.

## Where things live

| What                      | Source path                                                   |
| ------------------------- | ------------------------------------------------------------- |
| zsh entry                 | `dot_zshenv`, `dot_zshrc` (just sources the files below)      |
| zsh init / aliases / env  | `private_dot_config/zsh/init.zsh` ← **most zsh edits go here** |
| zsh plugins               | `private_dot_config/zsh/plugins.zsh`                          |
| zsh helpers               | `private_dot_config/zsh/utils.zsh`                            |
| git config                | `dot_gitconfig.tmpl` (templated; macOS-only extras in `private_dot_config/git/gitconfig_darwin`) |
| starship prompt           | `private_dot_config/starship.toml`                            |
| tmux                      | `dot_tmux.conf` (stub), `private_dot_config/tmux/tmux.conf`   |
| neovim                    | `private_dot_config/nvim/` (`init.lua`, `lua/config/*`, `lua/plugins/*`) |
| ghostty                   | `private_dot_config/ghostty/`                                 |
| atuin                     | `private_dot_config/atuin/config.toml`                        |
| direnv                    | `private_dot_config/direnv/direnv.toml`                       |
| nix daemon config         | `private_dot_config/nix/nix.conf`                             |
| nixy (Homebrew-style Nix) | `private_dot_config/nixy/` — **see below**                    |
| Claude Code               | `dot_claude/` (skills, settings, statusline)                  |
| Codex CLI                 | `dot_codex/private_config.toml`                               |

## Conventions

### Aliases & env

- All zsh aliases live in **`private_dot_config/zsh/init.zsh`**, grouped by tool
  and gated by `if type "<cmd>" > /dev/null; then ...` so the same file works on
  hosts without that tool installed. Add new aliases there, not in `dot_zshrc`.
- `dot_zshenv` is for env vars that **must** be set for non-interactive shells
  only. Everything else (PATH manipulation that depends on tools, completions,
  plugin loading) belongs in `init.zsh`.

### Templates

- `*.tmpl` files are rendered by chezmoi. Branch on OS with
  `{{- if eq .chezmoi.os "darwin" }} ... {{- end }}`.
- Don't add macOS-only blocks unconditionally — `.chezmoiignore` also excludes
  `gitconfig_darwin` on non-darwin.

### Nixy (package manager)

- Installed packages are tracked in `private_dot_config/nixy/nixy.json`
  (active profile `default`, also a `work` profile exists).
- **Don't hand-edit `nixy.json`.** Use:
  ```sh
  nixy install <pkg>     # alias: add
  nixy uninstall <pkg>   # alias: remove
  nixy upgrade
  ```
  Then commit the resulting `nixy.json` change.
- Custom flake-based packages live under `private_dot_config/nixy/packages/<name>/flake.nix`
  (e.g. `hunk`, `rtk`, `gke-gcloud-auth-plugin`).
- After `nixy` commands, `chezmoi apply` may report `nixy.json has changed`. That's
  normal (nixy wrote it, not chezmoi). Either re-add (`chezmoi re-add ~/.config/nixy/nixy.json`)
  or `chezmoi apply --force` only the files you actually changed.

### Claude Code skills

- Skills live in `dot_claude/skills/<name>/SKILL.md` and ship to `~/.claude/skills/`.
- Settings template: `dot_claude/private_settings.json.tmpl`.

## Pitfalls / gotchas

- **Editing `~/.gitconfig` directly does nothing persistent** — it's regenerated
  from `dot_gitconfig.tmpl`. Edit the template, or use `chezmoi edit ~/.gitconfig`.
- **`chezmoi re-add`** copies target → source but **loses templating**. For
  `*.tmpl` files, edit the template manually instead.
- **`chezmoi apply` without args** processes everything; if some unrelated file
  (often `nixy.json`) was modified out-of-band, it will block with a TTY prompt
  in non-interactive contexts. Pass specific targets and/or `--force` for them.
- Commit messages use a `<scope>: <what>` prefix (e.g. `zsh:`, `git:`, `nvim:`).
- The repo is pushed to `github.com:yusukeshib/dotfiles.git` on `main`.

## Quick reference commands

```sh
chezmoi source-path                  # repo root: ~/.local/share/chezmoi
chezmoi source-path ~/.zshrc         # target → source
chezmoi managed | grep <pattern>     # list what chezmoi controls
chezmoi diff ~/.zshrc                # preview pending changes
chezmoi apply ~/.zshrc               # apply one file
chezmoi cd                           # cd into source repo
```
