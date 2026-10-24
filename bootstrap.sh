#!/usr/bin/env bash
# Fresh-machine setup for the dotfiles repo.
#   git clone git@github.com:yusukeshib/dotfiles.git ~/dotfiles
#   ~/dotfiles/bootstrap.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Symlinking dotfiles into \$HOME (existing files backed up to *.predots-*)"
"$REPO/bin/dots" link

ZSH_PLUGIN_DIR="$HOME/.zsh/plugins"
mkdir -p "$ZSH_PLUGIN_DIR"
for repo in zsh-users/zsh-completions \
            zsh-users/zsh-autosuggestions \
            zsh-users/zsh-history-substring-search \
            Aloxaf/fzf-tab \
            romkatv/gitstatus \
            zsh-users/zsh-syntax-highlighting; do
  name="${repo##*/}"
  if [ ! -d "$ZSH_PLUGIN_DIR/$name" ]; then
    echo "==> Installing zsh plugin $repo"
    git clone --depth=1 "https://github.com/$repo" "$ZSH_PLUGIN_DIR/$name"
  fi
done
# Prefetch gitstatusd (used by the prompt) so the first shell doesn't download it.
"$ZSH_PLUGIN_DIR/gitstatus/install"

# TPM uses ~/.config/tmux/plugins/ because tmux.conf lives in the XDG location.
TPM_DIR="$HOME/.config/tmux/plugins/tpm"
if [ ! -d "$TPM_DIR" ]; then
  echo "==> Installing the tmux plugin manager"
  mkdir -p "$(dirname "$TPM_DIR")"
  git clone --depth=1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi
if command -v tmux >/dev/null 2>&1; then
  echo "==> Installing tmux plugins"
  "$TPM_DIR/bin/install_plugins"
  tmux_plugins=installed
else
  tmux_plugins=pending
fi

echo "==> Done. Install packages:  brew bundle --file=~/Brewfile"
if [ "$tmux_plugins" = pending ]; then
  echo "    tmux was not installed yet, so its plugins were skipped. After brew bundle:"
  echo "      $TPM_DIR/bin/install_plugins"
fi
echo "    Open a new shell:        exec zsh"
echo "    Check symlink health:    dots status"
