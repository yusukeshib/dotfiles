PLUGIN_DIR="$HOME/.zsh/plugins"

_load_plugin() {
  local repo=$1 name=${1##*/}
  local dir="$PLUGIN_DIR/$name"
  if [[ ! -d $dir ]]; then
    print -u2 "zsh plugin missing: $repo (run ~/dotfiles/bootstrap.sh)"
    return 1
  fi
  local file
  for file in "$dir/$name.plugin.zsh" "$dir/$name.zsh"; do
    [[ -r $file ]] || continue
    # Byte-compile once per plugin update; source prefers a fresh .zwc.
    [[ -s $file.zwc && $file.zwc -nt $file ]] || zcompile -R "$file" 2>/dev/null
    source "$file"
    return
  done
  return 1
}

_load_plugin zsh-users/zsh-completions

# compinit: regenerate dump at most once per 24h for fast startup.
autoload -Uz compinit
_zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"
# NOTE: glob qualifiers are NOT expanded inside [[ ]] — the old
# `[[ -n $_zcompdump(#qN.mh+24) ]]` was always true, so every shell paid for a
# full compinit + compaudit + compdump rewrite. Expand in an array instead
# (N.mh+24 = modified >24h ago, empty when fresh or missing).
_zcompstale=($_zcompdump(N.mh+24))
if [[ ! -s $_zcompdump ]] || (( $#_zcompstale )); then
  compinit -d "$_zcompdump"
  # compinit rewrites the dump only when it is actually invalid, so refresh the
  # mtime ourselves — otherwise a still-valid but old dump would take this slow
  # path on every startup forever.
  touch "$_zcompdump"
else
  compinit -C -d "$_zcompdump"
fi
unset _zcompstale
# Byte-compile the dump: compinit loads the .zwc instead of parsing ~60KB of
# zsh on every startup (~15ms -> ~8ms). Recompile only when the dump changed.
if [[ ! -s $_zcompdump.zwc || $_zcompdump.zwc -ot $_zcompdump ]]; then
  zcompile -R -- "$_zcompdump" 2>/dev/null
fi
unset _zcompdump

_load_plugin zsh-users/zsh-autosuggestions
_load_plugin zsh-users/zsh-history-substring-search
_load_plugin Aloxaf/fzf-tab
# Syntax highlighting is loaded at the end of init.zsh, after native widgets.
