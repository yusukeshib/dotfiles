export ZPLUG_HOME=${ZPLUG_HOME:-$HOME/.zplug}

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
