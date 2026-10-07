# Keep zshenv minimal: only env vars that must apply to non-interactive shells.
# Heavy initializations (Nix daemon profile, completions, etc.) belong in zshrc.

export LANG=en_US.UTF-8
# --hidden so dotfiles are searchable; --exclude .git keeps the repo internals out.
# (.fdignore + .gitignore are still honored.) The old `-i` was a no-op without a pattern.
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
export EDITOR=nvim

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
if [[ -d /opt/homebrew/opt/ffmpeg@7/bin ]]; then
  path=(
    /opt/homebrew/opt/ffmpeg@7/bin
    $path
  )
fi
export PATH
[[ -r "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

