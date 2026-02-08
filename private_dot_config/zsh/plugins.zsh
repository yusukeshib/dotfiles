PLUGIN_DIR="$HOME/.zsh/plugins"

_load_plugin() {
  local repo=$1 name=${1##*/}
  if [[ ! -d "$PLUGIN_DIR/$name" ]]; then
    git clone --depth=1 "https://github.com/$repo" "$PLUGIN_DIR/$name"
  fi
  source "$PLUGIN_DIR/$name/$name.plugin.zsh" 2>/dev/null \
    || source "$PLUGIN_DIR/$name/$name.zsh" 2>/dev/null
}

OMZ_DIR="$PLUGIN_DIR/ohmyzsh"

_load_omz_plugin() {
  local name=$1
  if [[ ! -d "$OMZ_DIR" ]]; then
    git clone --depth=1 "https://github.com/ohmyzsh/ohmyzsh" "$OMZ_DIR"
  fi
  [[ -f "$OMZ_DIR/lib/$name.zsh" ]] && source "$OMZ_DIR/lib/$name.zsh"
  source "$OMZ_DIR/plugins/$name/$name.plugin.zsh" 2>/dev/null
}

_load_omz_plugin git

_load_plugin zsh-users/zsh-completions
autoload -Uz compinit && compinit
_load_plugin zsh-users/zsh-autosuggestions
_load_plugin zsh-users/zsh-history-substring-search
_load_plugin Aloxaf/fzf-tab
_load_plugin zsh-users/zsh-syntax-highlighting  # must be last
