bindkey -e
unsetopt BEEP

# Nix daemon profile (moved from zshenv to avoid side effects in non-interactive shells)
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

# Cache directory for generated completion scripts
export ZSH_CACHE_DIR="${ZSH_CACHE_DIR:-$HOME/.cache/zsh}"
[[ -d $ZSH_CACHE_DIR ]] || mkdir -p "$ZSH_CACHE_DIR"

# Helper: source `$1 <cmd...>` output via cached file, regenerating once per day.
_cached_eval() {
  local name=$1; shift
  local cache="$ZSH_CACHE_DIR/$name.zsh"
  if [[ ! -s $cache || -n $cache(#qN.mh+24) ]]; then
    "$@" > "$cache" 2>/dev/null || { rm -f "$cache"; return 1 }
  fi
  source "$cache"
}

if type "nixy" > /dev/null; then
  _cached_eval nixy nixy config zsh
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

if type "zoxide" > /dev/null; then
  eval "$(zoxide init zsh)"
fi

if type "kubectl" > /dev/null; then
  _cached_eval kubectl kubectl completion zsh
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
fi

if type "nvim" > /dev/null; then
  alias vi="nvim"
  alias vim="nvim"
  export EDITOR="nvim"
fi

# Use `bcat` (not `cat`) to avoid breaking scripts that pipe through cat.
if type "batcat" > /dev/null; then
  alias bcat="batcat"
elif type "bat" > /dev/null; then
  alias bcat="bat"
fi

if type "rg" > /dev/null; then
  alias rg="rg --hidden -g '!.git/'"
fi

if type "difft" > /dev/null; then
  # Override oh-my-zsh git plugin's `gd` to use difftastic
  alias gd='git -c diff.external=difft diff'
fi


if type "atuin" > /dev/null; then
  eval "$(atuin init zsh --disable-up-arrow)"
  bindkey '^r' atuin-search
fi

if type "box" > /dev/null; then
  _cached_eval box box config zsh
fi
