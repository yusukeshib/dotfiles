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
            zsh-users/zsh-syntax-highlighting; do
  name="${repo##*/}"
  if [ ! -d "$ZSH_PLUGIN_DIR/$name" ]; then
    echo "==> Installing zsh plugin $repo"
    git clone --depth=1 "https://github.com/$repo" "$ZSH_PLUGIN_DIR/$name"
  fi
done

TPM_DIR="$HOME/.tmux/plugins/tpm"
if [ ! -d "$TPM_DIR" ]; then
  echo "==> Installing the tmux plugin manager"
  mkdir -p "$(dirname "$TPM_DIR")"
  git clone --depth=1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi
if command -v tmux >/dev/null 2>&1; then
  "$TPM_DIR/bin/install_plugins"
fi

echo "==> Done. Install packages:  brew bundle --file=~/Brewfile"
echo "    Install tmux plugins:    ~/.tmux/plugins/tpm/bin/install_plugins"
echo "    Open a new shell:        exec zsh"
echo "    Check symlink health:    dots status"
