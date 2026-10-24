# Native zsh prompt (replaces starship). Git info comes from gitstatusd, a
# long-lived daemon, so rendering a prompt never execs an external binary.
# Layout mirrors the former starship config:
#
#   <blank line>
#    host  ~/dir on branch (ACTION) [status] took 3s
#   ✦1 >

autoload -Uz add-zsh-hook
zmodload zsh/datetime

# Per-host badge color, derived from cksum($HOST) like the old starship palette.
# Cached so cksum runs once per host, not per shell.
() {
  local cache="$ZSH_CACHE_DIR/prompt-host-color-$HOST" checksum bytes
  local -a colors
  if [[ $OSTYPE == darwin* ]]; then
    colors=( magenta blue red cyan )
  else
    colors=( cyan red yellow green blue magenta )
  fi
  if [[ -r $cache ]]; then
    IFS= read -r checksum < "$cache"
  fi
  if [[ $checksum != <-> ]]; then
    read -r checksum bytes < <(printf '%s' "$HOST" | cksum)
    print -r -- "$checksum" > "$cache"
  fi
  typeset -g _prompt_host="%B%F{black}%K{${colors[checksum % $#colors + 1]}} %m %k%f%b "
}

typeset -g _prompt_git= _prompt_git_workdir= _prompt_duration=
typeset -gF _prompt_cmd_start=0
typeset -gi _prompt_gitstatus=0 _prompt_git_pending=0

# Sourced directly: gitstatus.plugin.zsh treats $1 as a function-name suffix,
# and _load_plugin's own arguments would leak into it.
if [[ -r $PLUGIN_DIR/gitstatus/gitstatus.plugin.zsh ]] &&
   source "$PLUGIN_DIR/gitstatus/gitstatus.plugin.zsh" ""; then
  # Launch the daemon now without waiting; the handshake completes on the
  # first precmd so its exec latency overlaps the rest of shell init.
  # -s/-u/-c/-d 1: we only need "is there any", not counts.
  gitstatus_start -a -s 1 -u 1 -c 1 -d 1 PROMPT && _prompt_gitstatus=1
fi

_prompt_git_render() {
  emulate -L zsh
  if [[ $VCS_STATUS_RESULT != ok-* ]]; then
    _prompt_git= _prompt_git_workdir=
    return
  fi
  _prompt_git_workdir=$VCS_STATUS_WORKDIR
  local out
  if [[ -n $VCS_STATUS_LOCAL_BRANCH ]]; then
    out="on %B%F{magenta}${VCS_STATUS_LOCAL_BRANCH//\%/%%}"
    if [[ -n $VCS_STATUS_REMOTE_BRANCH && $VCS_STATUS_REMOTE_BRANCH != $VCS_STATUS_LOCAL_BRANCH ]]; then
      out+=":${VCS_STATUS_REMOTE_BRANCH//\%/%%}"
    fi
    out+="%f%b "
  else
    out="%B%F{green}(${VCS_STATUS_COMMIT[1,7]})%f%b "
  fi
  if [[ -n $VCS_STATUS_ACTION ]]; then
    local action=${(U)VCS_STATUS_ACTION}
    case $VCS_STATUS_ACTION in
      rebase*) action=REBASING ;;
      merge) action=MERGING ;;
      cherry-pick*) action=CHERRY-PICKING ;;
      revert*) action=REVERTING ;;
      bisect) action=BISECTING ;;
    esac
    out+="(%B%F{yellow}${action//\%/%%}%f%b) "
  fi
  local st=
  (( VCS_STATUS_NUM_CONFLICTED > 0 )) && st+='='
  (( VCS_STATUS_STASHES > 0 )) && st+='$'
  (( VCS_STATUS_NUM_STAGED_DELETED + VCS_STATUS_NUM_UNSTAGED_DELETED > 0 )) && st+='x'
  (( VCS_STATUS_NUM_UNSTAGED > VCS_STATUS_NUM_UNSTAGED_DELETED || VCS_STATUS_HAS_UNSTAGED < 0 )) && st+='!'
  (( VCS_STATUS_NUM_STAGED > 0 )) && st+='+'
  (( VCS_STATUS_HAS_UNTRACKED != 0 )) && st+='?'
  if (( VCS_STATUS_COMMITS_AHEAD && VCS_STATUS_COMMITS_BEHIND )); then
    st+='<>'
  elif (( VCS_STATUS_COMMITS_AHEAD )); then
    st+='>'
  elif (( VCS_STATUS_COMMITS_BEHIND )); then
    st+='<'
  fi
  [[ -n $st ]] && out+="%B%F{red}[${st//\%/%%}]%f%b "
  _prompt_git=$out
}

_prompt_render() {
  emulate -L zsh
  local dir=${(%):-%~}
  local -a parts=(${(s:/:)dir})
  (( $#parts > 2 )) && dir=".../${(j:/:)parts[-2,-1]}"
  dir="%B%F{cyan}${dir//\%/%%}%f%b"
  [[ -w $PWD ]] || dir+="%F{red} ro%f"
  PROMPT=$'\n'"${_prompt_host}${dir} ${_prompt_git}${_prompt_duration}"$'\n'
  PROMPT+='%(1j.%B%F{blue}✦%j%f%b .)%(?.%B%F{green}>%f%b.%B%F{red}x%f%b) '
}

_prompt_gitstatus_callback() {
  emulate -L zsh
  _prompt_git_pending=0
  _prompt_git_render
  _prompt_render
  zle && zle .reset-prompt
}

_prompt_preexec() {
  _prompt_cmd_start=$EPOCHREALTIME
}

_prompt_precmd() {
  emulate -L zsh
  _prompt_duration=
  if (( _prompt_cmd_start > 0 )); then
    local -i secs=$(( EPOCHREALTIME - _prompt_cmd_start ))
    _prompt_cmd_start=0
    if (( secs >= 2 )); then
      local d=
      (( secs >= 3600 )) && d+="$(( secs / 3600 ))h"
      (( secs >= 60 )) && d+="$(( secs % 3600 / 60 ))m"
      d+="$(( secs % 60 ))s"
      _prompt_duration="took %B%F{yellow}$d%f%b "
    fi
  fi

  if (( _prompt_gitstatus )); then
    # Completes the handshake on the first prompt; no-op afterwards.
    if ! gitstatus_start -s 1 -u 1 -c 1 -d 1 PROMPT; then
      _prompt_gitstatus=0
      _prompt_git=
    elif (( _prompt_git_pending )); then
      # A query is still in flight (concurrent queries are not allowed); its
      # callback will refresh the prompt.
      [[ -n $_prompt_git_workdir && $PWD/ == $_prompt_git_workdir/* ]] || _prompt_git=
    elif gitstatus_query -t 0.05 -c _prompt_gitstatus_callback PROMPT; then
      if [[ $VCS_STATUS_RESULT == tout ]]; then
        _prompt_git_pending=1
        # Keep the previous git segment only while still inside that repo.
        [[ -n $_prompt_git_workdir && $PWD/ == $_prompt_git_workdir/* ]] || _prompt_git=
      else
        _prompt_git_render
      fi
    else
      _prompt_git=
    fi
  fi
  _prompt_render
}

add-zsh-hook preexec _prompt_preexec
add-zsh-hook precmd _prompt_precmd
PROMPT2='%F{8}∙%f '
RPROMPT=
_prompt_render
