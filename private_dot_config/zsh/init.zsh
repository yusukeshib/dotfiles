bindkey -e
unsetopt BEEP

# Nix
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export FZF_DEFAULT_COMMAND='fd --type f -i'
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
export BOX_DEFAULT_CMD="claude"

if type "nixy" > /dev/null; then
  eval "$(nixy config zsh)"
fi

#
# Plugins (must come before native integrations that use compdef)
#

source ${0:A:h}/plugins.zsh

#
# Native tool integrations
#

if type "starship" > /dev/null; then
  eval "$(starship init zsh)"
fi

if type "direnv" > /dev/null; then
  eval "$(direnv hook zsh)"
fi

if type "fzf" > /dev/null; then
  source <(fzf --zsh)
fi

if type "kubectl" > /dev/null; then
  source <(kubectl completion zsh)
  alias k="kubectl"
fi

#
# Aliases
#

# eza
if type "eza" > /dev/null; then
  alias ls='eza'
  alias ll='eza -lg'
  alias la='eza -la'
  alias lt='eza --tree'
fi

if type "tmux" > /dev/null; then
  new() {
    if (( $# == 0 )); then
      print -u2 "usage: new <session-name>"
      return 1
    fi

    if [[ -n "${TMUX:-}" ]]; then
      tmux has-session -t "$1" 2>/dev/null || tmux new-session -d -s "$1"
      tmux switch-client -t "$1"
    else
      tmux new-session -A -s "$1"
    fi
  }

  a() {
    if (( $# == 0 )); then
      if [[ -n "${TMUX:-}" ]]; then
        tmux choose-tree -Zs
      else
        tmux attach-session
      fi
      return
    fi

    if [[ -n "${TMUX:-}" ]]; then
      tmux switch-client -t "$1"
    else
      tmux attach-session -t "$1"
    fi
  }

  _tmux_attach_sessions() {
    local -a sessions
    sessions=("${(@f)$(tmux list-sessions -F '#S' 2>/dev/null)}")
    if (( ! $#sessions )); then
      _message 'no sessions'
      return 1
    fi
    compadd -S '' -Q -a sessions
  }

  compdef _tmux_attach_sessions a

  zstyle ':fzf-tab:complete:a:*' fzf-preview \
    'echo "tmux session: $word"; echo; tmux list-sessions -F "#S" | grep --color=always -E "^${word//\*/.*}$" || true'
elif type "zellij" > /dev/null; then
  alias new="zellij -s"

  # Note: defining 'a' as a function is more stable
  a() { zellij attach "$@"; }

  _zellij_attach_sessions() {
    local -a sessions
    # Important: use `list-sessions` (not `ls`)
    sessions=("${(@f)$(zellij list-sessions --short 2>/dev/null)}")
    if (( ! $#sessions )); then
      _message 'no sessions'
      return 1
    fi
    compadd -S '' -Q -a sessions
  }

  # Bind completion function to 'a' (required)
  compdef _zellij_attach_sessions a

  # fzf-tab preview (optional)
  zstyle ':fzf-tab:complete:a:*' fzf-preview \
    'echo "Zellij session: $word"; echo; zellij list-sessions --short | grep --color=always -E "^${word//\*/.*}$" || true'
fi

if type "nvim" > /dev/null; then
  alias vi="nvim"
  alias vim="nvim"
  export EDITOR="nvim"
fi

if type "batcat" > /dev/null; then
  alias cat="batcat"
elif type "bat" > /dev/null; then
  alias cat="bat"
fi

if type "rg" > /dev/null; then
  alias rg="rg --hidden -g '!.git/'"
fi


if type "atuin" > /dev/null; then
  eval "$(atuin init zsh --disable-up-arrow)"
  bindkey '^r' atuin-search
fi

if type "box" > /dev/null; then
  eval "$(box config zsh)";
fi
