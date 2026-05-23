# dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/).

## What's included

| Tool        | Path                                    |
| ----------- | --------------------------------------- |
| zsh         | `dot_zshenv`, `dot_zshrc`, `private_dot_config/zsh/` |
| git         | `dot_gitconfig.tmpl`, `private_dot_config/git/`      |
| starship    | `private_dot_config/starship.toml`      |
| tmux        | `private_dot_config/tmux/`              |
| neovim      | `private_dot_config/nvim/`              |
| ghostty     | `private_dot_config/ghostty/`           |
| atuin       | `private_dot_config/private_atuin/`     |
| direnv      | `private_dot_config/direnv/`            |
| nix / nixy  | `private_dot_config/nix/`, `private_dot_config/nixy/` |
| Claude Code | `dot_claude/`                           |
| Codex CLI   | `dot_codex/`                            |

## Bootstrap (host machine)

```sh
nix profile add chezmoi
chezmoi init yusukeshib --ssh
chezmoi apply
```

## Dev container

A Debian-based image with the same dotfiles applied is provided.

```sh
# Build (uses buildkit cache mounts; first build is slow, subsequent builds fast)
DOCKER_BUILDKIT=1 docker build -t mydev .

# Run (mount a workspace)
docker run --rm -it -v "$PWD:/workspace" -w /workspace mydev
```

## Layout notes

- `dot_zshenv` keeps only env vars that must apply to non-interactive shells. All
  heavy initialization (Nix daemon, completions, plugin loading) lives in
  `private_dot_config/zsh/init.zsh`.
- Tool-specific completion scripts (`kubectl`, `nixy`, `box`, …) are cached
  under `~/.cache/zsh/*.zsh` and regenerated at most once per day via
  `_cached_eval`.
- zsh plugins are cloned shallowly into `~/.zsh/plugins`. Pin a commit by
  adding to `ZSH_PLUGIN_REV` in `plugins.zsh`.
- `compinit` uses a 24h-cached `.zcompdump` for faster shell startup.
- Templates (`*.tmpl`) branch on `.chezmoi.os` so the same source serves macOS
  and Linux without leaking macOS-only hooks (e.g. `terminal-notifier`,
  1Password `op-ssh-sign`).
