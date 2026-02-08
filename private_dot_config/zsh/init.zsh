bindkey -e
unsetopt BEEP

# Nix
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

export TERM=xterm-256color
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export FZF_DEFAULT_COMMAND='fd --type f -i'
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
export PATH=$HOME/.opencode/bin:$PATH
export ZPLUG_HOME=$HOME/.zplug
export REALM_DOCKERFILE=$HOME/Dockerfile

if type "nixy" > /dev/null; then
  eval "$(nixy config zsh)"
fi

#
# zplug
#


if [[ ! -d "$ZPLUG_HOME" ]]; then
  git clone https://github.com/zplug/zplug $ZPLUG_HOME
fi

if [ -d "$ZPLUG_HOME" ]; then
  source $ZPLUG_HOME/init.zsh

  zplug "plugins/asdf", from:oh-my-zsh
  zplug "plugins/brew", from:oh-my-zsh
  zplug "plugins/common-aliases", from:oh-my-zsh

  if type "direnv" > /dev/null; then
    zplug "plugins/direnv", from:oh-my-zsh
  fi

  zplug "plugins/eza", from:oh-my-zsh
  zplug "plugins/fzf", from:oh-my-zsh
  zplug "plugins/git", from:oh-my-zsh
  zplug "plugins/kubectl", from:oh-my-zsh

  if type "starship" > /dev/null; then
    zplug "plugins/starship", from:oh-my-zsh
  fi

  zplug "zsh-users/zsh-autosuggestions"
  zplug "zsh-users/zsh-history-substring-search"
  zplug "zsh-users/zsh-syntax-highlighting"
  zplug "zsh-users/zsh-completions"
  zplug "Aloxaf/fzf-tab", use:"fzf-tab.plugin.zsh"
  
  if ! zplug check --verbose; then
      printf "Install? [y/N]: "
      if read -q; then
          echo; zplug install
      fi
  fi
  zplug load
fi


#
# Aliases
#

if type "zellij" > /dev/null; then
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

if type "wt" > /dev/null; then
  eval "$(wt config shell init zsh)";
fi
