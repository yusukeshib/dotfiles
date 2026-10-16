# Keep zshenv minimal: only env vars that must apply to non-interactive shells.
# Tool-dependent PATH entries, completions, and plugins belong in
# ~/.config/zsh/init.zsh (sourced by zshrc).

export LANG=en_US.UTF-8
# --hidden so dotfiles are searchable; --exclude .git keeps the repo internals out.
# (.fdignore + .gitignore are still honored.) The old `-i` was a no-op without a pattern.
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
export EDITOR=nvim

# pi coding agent: request the provider's long prompt-cache retention (pi-ai
# maps it for Anthropic and OpenAI APIs) so pauses between turns don't force a
# full re-prefill. Exported here so non-interactive `pi -p` runs get it too.
export PI_CACHE_RETENTION=long

# PATH: prefer user-local binaries
typeset -U path
path=(
  "$HOME/.local/bin"
  "$HOME/.cargo/bin"
  $path
)
if [[ -d /home/linuxbrew/.linuxbrew/bin ]]; then
  path=(
    /home/linuxbrew/.linuxbrew/bin
    /home/linuxbrew/.linuxbrew/sbin
    $path
  )
fi
export PATH
[[ -r "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

