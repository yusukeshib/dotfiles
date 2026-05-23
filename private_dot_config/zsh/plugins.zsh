PLUGIN_DIR="$HOME/.zsh/plugins"

# Per-plugin commit pins (optional). Empty -> latest from --depth=1 clone.
# Bump these intentionally; reproducibility > convenience.
typeset -gA ZSH_PLUGIN_REV=(
  # [zsh-users/zsh-completions]=""
  # [zsh-users/zsh-autosuggestions]=""
  # [zsh-users/zsh-history-substring-search]=""
  # [Aloxaf/fzf-tab]=""
  # [zsh-users/zsh-syntax-highlighting]=""
)

_load_plugin() {
  local repo=$1 name=${1##*/} rev=${ZSH_PLUGIN_REV[$1]:-}
  local dir="$PLUGIN_DIR/$name"
  if [[ ! -d $dir ]]; then
    if [[ -n $rev ]]; then
      git clone "https://github.com/$repo" "$dir" && git -C "$dir" checkout --quiet "$rev"
    else
      git clone --depth=1 "https://github.com/$repo" "$dir"
    fi
  fi
  source "$dir/$name.plugin.zsh" 2>/dev/null \
    || source "$dir/$name.zsh" 2>/dev/null
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

# compinit: regenerate dump at most once per 24h for fast startup.
autoload -Uz compinit
_zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"
if [[ -n $_zcompdump(#qN.mh+24) || ! -s $_zcompdump ]]; then
  compinit -d "$_zcompdump"
else
  compinit -C -d "$_zcompdump"
fi
unset _zcompdump

_load_plugin zsh-users/zsh-autosuggestions
_load_plugin zsh-users/zsh-history-substring-search
_load_plugin Aloxaf/fzf-tab
_load_plugin zsh-users/zsh-syntax-highlighting  # must be last
