bindkey -e
unsetopt BEEP

# User-local binaries (cargo-installed babysit/goal, ~/.local/bin/pi, dotfiles
# helpers) must win over Homebrew and system copies. macOS /etc/zprofile's
# path_helper, `brew shellenv`, and the gcloud include all prepend entries
# after zshenv, so re-assert the order after each of them. typeset -U keeps the
# first occurrence, which moves existing entries to the front.
typeset -U path
_prefer_user_paths() {
  path=(
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
    "$HOME/dotfiles/bin"(N/)
    $path
  )
}
_prefer_user_paths

# Cache directory for generated completion/init scripts
export ZSH_CACHE_DIR="${ZSH_CACHE_DIR:-$HOME/.cache/zsh}"
[[ -d $ZSH_CACHE_DIR ]] || mkdir -p "$ZSH_CACHE_DIR"

# Cache generated shell code by resolved producer path and arguments as well
# as mtime: a newly installed Homebrew binary can have an older build timestamp.
# Fall back to a 24h TTL if the command has no real path.
_cached_eval() {
  local name=$1; shift
  local cache="$ZSH_CACHE_DIR/$name.zsh"
  # Resolve the generating command to a real file ($1 may already be a path);
  # :A follows symlinks, so a Homebrew relink into a new Cellar dir is seen.
  local bin=${commands[$1]:-$1}
  [[ -x $bin ]] && bin=${bin:A} || bin=
  local identity="# cached-eval: ${(qqq)bin} ${(j: :)${(qqq)@}}"
  local cached_identity=
  [[ -r $cache ]] && IFS= read -r cached_identity < "$cache"
  local stale=0
  if [[ ! -s $cache || $cached_identity != $identity ]]; then
    stale=1
  elif [[ -n $bin ]]; then
    # -nt/-ot stat the target, so this compares real binary vs cache mtime.
    [[ $cache -ot $bin ]] && stale=1
  else
    # NOTE: glob qualifiers are NOT expanded inside [[ ]]. (N.mh+24) = modified
    # >24h ago (empty if fresh); the #q prefix form would need EXTENDED_GLOB.
    local -a old=($cache(N.mh+24))
    (( $#old )) && stale=1
  fi
  if (( stale )); then
    local tmp
    tmp=$(mktemp "$cache.XXXXXXXX") || return 1
    if ! { print -r -- "$identity" && "$@"; } > "$tmp" 2>/dev/null; then
      rm -f "$tmp"
      return 1
    fi
    # Never publish a partial generation or keep bytecode for the old producer.
    rm -f "$cache.zwc"
    mv -f "$tmp" "$cache" || { rm -f "$tmp"; return 1 }
    zcompile -R "$cache" 2>/dev/null
  fi
  source "$cache"
}

# Homebrew: use the platform's default prefix (Apple Silicon/Intel macOS or
# Linuxbrew) and initialize it before checking for tool integrations below.
# `brew shellenv` costs ~12ms (Ruby/bash startup) and its output is static, so
# it goes through the cache like every other init snippet.
for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew \
             /home/linuxbrew/.linuxbrew/bin/brew ${commands[brew]}; do
  if [[ -x $_brew ]]; then
    _cached_eval brew-shellenv "$_brew" shellenv zsh
    break
  fi
done
unset _brew
# ffmpeg@7 is keg-only; expose it ahead of any unversioned ffmpeg.
if [[ -n $HOMEBREW_PREFIX && -d $HOMEBREW_PREFIX/opt/ffmpeg@7/bin ]]; then
  path=("$HOMEBREW_PREFIX/opt/ffmpeg@7/bin" $path)
fi
_prefer_user_paths

# History: persist to file and share across sessions. atuin has its own DB,
# but zsh-history-substring-search (and plain zsh) read from this file.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY        # share history across concurrent sessions
setopt HIST_IGNORE_DUPS     # don't record consecutive duplicates
setopt HIST_IGNORE_SPACE    # don't record commands starting with a space
setopt HIST_REDUCE_BLANKS   # strip superfluous whitespace

# In WSL, route Git's SSH transport through Windows OpenSSH so it can use the
# 1Password SSH agent running on the Windows host.
if [[ -r /proc/version ]] && grep -qi microsoft /proc/version && (( $+commands[ssh.exe] )); then
  export GIT_SSH_COMMAND=ssh.exe
fi

#
# Plugins (must come before native integrations that use compdef)
#

source ${0:A:h}/plugins.zsh

# history-substring-search: type a prefix, then ↑/↓ to cycle matches.
# atuin uses --disable-up-arrow, so the arrow keys are free for this.
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

#
# Native tool integrations
#

# Prompt: native zsh + gitstatusd; no external exec per prompt.
source ${0:A:h}/prompt.zsh

# Machine-local, untracked environment (API keys etc.). Formerly ~/.envrc via
# direnv, which forced a direnv exec on every prompt everywhere under $HOME.
[[ -r $HOME/.config/zsh/local.zsh ]] && source "$HOME/.config/zsh/local.zsh"

if type "direnv" > /dev/null; then
  _cached_eval direnv direnv hook zsh
  # direnv's hook execs `direnv export` on every prompt. Run it only when an
  # .envrc exists in $PWD or an ancestor, or when an environment is loaded and
  # may need unloading ($DIRENV_DIR). This check is a few stat calls.
  _direnv_gate() {
    if [[ -z $DIRENV_DIR ]]; then
      local d=$PWD
      while [[ ! -e $d/.envrc ]]; do
        [[ $d == / ]] && return 0
        d=${d:h}
      done
    fi
    _direnv_hook
  }
  add-zsh-hook -d precmd _direnv_hook
  add-zsh-hook -d chpwd _direnv_hook
  add-zsh-hook precmd _direnv_gate
  add-zsh-hook chpwd _direnv_gate
fi

if type "fzf" > /dev/null; then
  _cached_eval fzf fzf --zsh
fi

if type "zoxide" > /dev/null; then
  _cached_eval zoxide zoxide init zsh
fi

if type "kubectl" > /dev/null; then
  _cached_eval kubectl kubectl completion zsh
  alias k="kubectl"
  # make completion follow the alias (kubectl's compdef only wires the full name)
  compdef k=kubectl
fi

#
# Aliases
#

# Session helpers for tmux.
if type "tmux" > /dev/null; then
  _tmux_new() {
    if [[ -n "${TMUX:-}" ]]; then
      tmux has-session -t "$1" 2>/dev/null || tmux new-session -d -s "$1"
      tmux switch-client -t "$1"
    else
      tmux new-session -A -s "$1"
    fi
  }

  _tmux_attach() {
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

  tnew() { _tmux_new "$@" }
  ta() { _tmux_attach "$@" }

  new() {
    if (( $# == 0 )); then
      print -u2 "usage: new <session-name>"
      return 1
    fi

    _tmux_new "$@"
  }

  a() { _tmux_attach "$@" }

  _tmux_sessions_comp() {
    local -a sessions
    sessions=("${(@f)$(tmux list-sessions -F '#S' 2>/dev/null)}")
    (( $#sessions )) || { _message 'no sessions'; return 1 }
    compadd -S '' -Q -a sessions
  }

  compdef _tmux_sessions_comp a ta

  zstyle ':fzf-tab:complete:a:*' fzf-preview \
    'echo "session: $word"'
  zstyle ':fzf-tab:complete:ta:*' fzf-preview \
    'echo "tmux session: $word"; echo; tmux list-sessions -F "#S" | grep --color=always -E "^${word//\*/.*}$" || true'
fi

if type "nvim" > /dev/null; then
  alias vi="nvim"
  alias vim="nvim"
fi

if type "lsd" > /dev/null; then
  alias ls='lsd'
  alias ll='lsd -l'
  alias la='lsd -a'
  alias lla='lsd -la'
  alias lt='lsd --tree'
fi

# git aliases (replaces the ohmyzsh git plugin)
# helper: name of the main branch (main/master/...)
function git_main_branch() {
  command git rev-parse --git-dir &>/dev/null || return
  local ref
  for ref in refs/{heads,remotes/{origin,upstream}}/{main,trunk,mainline,default,master}; do
    if command git show-ref -q --verify "$ref"; then
      echo "${ref##*/}"
      return
    fi
  done
  echo master
}
function git_current_branch() {
  command git symbolic-ref --short HEAD 2>/dev/null
}

alias g='git'

# dotfiles: normal git repo at ~/dotfiles (home/ and home-<platform>/ trees are
# symlinked into $HOME). ~/dotfiles/bin is on PATH via _prefer_user_paths.
# Manage symlinks with `dots` (link / status / relink / adopt / unlink).

# add
alias ga='git add'
alias gaa='git add --all'
alias gau='git add --update'

# branch
alias gb='git branch'
alias gba='git branch --all'
alias gbd='git branch --delete'
alias gbD='git branch --delete --force'
alias gbm='git branch --move'
alias gbnm='git branch --no-merged'
alias gbr='git branch --remote'
alias gbg='git branch -vv | grep ": gone\]"'

# checkout / switch
alias gco='git checkout'
alias gcb='git checkout -b'
alias gcB='git checkout -B'
alias gcm='git checkout $(git_main_branch)'
alias gcd='git checkout develop'
alias gcor='git checkout --recurse-submodules'
alias gsw='git switch'
alias gswc='git switch --create'
alias gswm='git switch $(git_main_branch)'
alias gswd='git switch develop'
alias grs='git restore'
alias grss='git restore --source'
alias grst='git restore --staged'

# commit
# Git never opens an editor (core.editor = true), so every commit alias must
# carry its message (--message) or keep the existing one (--no-edit).
alias gcam='git commit --all --message'
alias gcams='git commit --all --signoff --message'
alias gcmsg='git commit --message'
alias gcn!='git commit --no-edit --amend'
alias gcan!='git commit --all --no-edit --amend'
alias gcfx='git commit --fixup'

# clone
alias gcl='git clone --recurse-submodules'

# config
alias gcf='git config --list'

# diff
alias gd='git diff'
alias gdca='git diff --cached'
alias gds='git diff --staged'
alias gdw='git diff --word-diff'
alias gdup='git diff @{upstream}'
alias gdt='git diff-tree --no-commit-id --name-only -r'

# fetch
alias gf='git fetch'
alias gfa='git fetch --all --tags --prune'
alias gfo='git fetch origin'

# pull
alias gl='git pull'
alias gpr='git pull --rebase'
alias gprv='git pull --rebase -v'
alias gluc='git pull upstream $(git_current_branch)'
alias glum='git pull upstream $(git_main_branch)'
alias ggpull='git pull origin "$(git_current_branch)"'

# push
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gpf!='git push --force'
alias gpd='git push --dry-run'
alias gpsup='git push --set-upstream origin $(git_current_branch)'
alias gpsupf='git push --set-upstream origin $(git_current_branch) --force-with-lease'
alias gpoat='git push origin --all && git push origin --tags'
alias gpv='git push --verbose'
alias ggpush='git push origin "$(git_current_branch)"'

# log
alias glog='git log --oneline --decorate --graph'
alias gloga='git log --oneline --decorate --graph --all'
alias glol="git log --graph --pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset'"
alias glola="git log --graph --pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset' --all"
alias glols="git log --graph --pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset' --stat"
alias glo='git log --oneline --decorate'
alias glods="git log --graph --pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset' --date=short"
alias glp='git log --patch'
alias gcount='git shortlog --summary --numbered'

# rebase
alias grb='git rebase'
alias grba='git rebase --abort'
alias grbc='git rebase --continue'
alias grbs='git rebase --skip'
alias grbo='git rebase --onto'
alias grbm='git rebase $(git_main_branch)'
alias grbom='git rebase origin/$(git_main_branch)'
alias grbd='git rebase develop'

# reset
alias grh='git reset'
alias grhh='git reset --hard'
alias grhk='git reset --keep'
alias grhs='git reset --soft'
alias gru='git reset --'
alias gpristine='git reset --hard && git clean --force -dfx'
alias groh='git reset origin/$(git_current_branch) --hard'

# remote
alias gr='git remote'
alias gra='git remote add'
alias grv='git remote --verbose'
alias grrm='git remote remove'
alias grset='git remote set-url'
alias grup='git remote update'

# merge
alias gm='git merge'
alias gma='git merge --abort'
alias gmc='git merge --continue'
alias gms='git merge --squash'
alias gmom='git merge origin/$(git_main_branch)'
alias gmum='git merge upstream/$(git_main_branch)'

# status
alias gst='git status'
alias gss='git status --short'
alias gsb='git status --short --branch'

# stash
alias gsta='git stash push'
alias gstaa='git stash apply'
alias gstc='git stash clear'
alias gstd='git stash drop'
alias gstl='git stash list'
alias gstp='git stash pop'
alias gsts='git stash show --patch'
alias gstall='git stash --all'

# cherry-pick
alias gcp='git cherry-pick'
alias gcpa='git cherry-pick --abort'
alias gcpc='git cherry-pick --continue'

# clean / rm
alias grm='git rm'
alias grmc='git rm --cached'

# revert
alias grev='git revert'
alias greva='git revert --abort'
alias grevc='git revert --continue'

# show / blame / describe
alias gsh='git show'
alias gsps='git show --pretty=short --show-signature'
alias gbl='git blame -w'
# `git whatchanged` is deprecated; this is its documented `git log` equivalent.
alias gwch='git log --raw --no-merges -p --abbrev-commit --pretty=medium'

# tag
alias gtv='git tag | sort -V'

# worktree
alias gwt='git worktree'
alias gwta='git worktree add'
alias gwtls='git worktree list'
alias gwtrm='git worktree remove'

# bisect
alias gbs='git bisect'
alias gbsb='git bisect bad'
alias gbsg='git bisect good'
alias gbsr='git bisect reset'
alias gbss='git bisect start'

# submodule
alias gsi='git submodule init'
alias gsu='git submodule update'

# misc
alias gignore='git update-index --assume-unchanged'
alias gunignore='git update-index --no-assume-unchanged'
alias gwip='git add -A; git rm $(git ls-files --deleted) 2>/dev/null; git commit --no-verify --no-gpg-sign --message "--wip-- [skip ci]"'
alias gunwip='git rev-list --max-count=1 --format="%s" HEAD | grep -q -- "--wip--" && git reset HEAD~1'

# Use `bcat` (not `cat`) to avoid breaking scripts that pipe through cat.
if type "batcat" > /dev/null; then
  alias bcat="batcat"
elif type "bat" > /dev/null; then
  alias bcat="bat"
fi

if type "rg" > /dev/null; then
  alias rg="rg --hidden -g '!.git/'"
fi


if type "atuin" > /dev/null; then
  # Generate the session id (UUIDv7, simple format, as `atuin uuid` prints)
  # in-shell so the init below skips its `atuin uuid` exec.
  if [[ -z ${ATUIN_SESSION:-} || ${ATUIN_SHLVL:-} != $SHLVL ]]; then
    () {
      emulate -L zsh -o no_multibyte
      zmodload zsh/system zsh/datetime 2>/dev/null || return
      local buf c hex
      sysread -s 10 buf < /dev/urandom 2>/dev/null && (( $#buf == 10 )) || return
      for c in ${(s::)buf}; do hex+=${(l:2::0:)$(( [##16] #c ))}; done
      hex=${(L)hex}
      local -i ms=$(( ${EPOCHREALTIME%.*} * 1000 + 10#${${EPOCHREALTIME#*.}[1,3]} ))
      local ts=${(L)${(l:12::0:)$(( [##16] ms ))}}
      local -i v=$(( 0x${hex[4,5]} & 0x3f | 0x80 ))
      export ATUIN_SESSION="${ts}7${hex[1,3]}${(L)$(( [##16] v ))}${hex[6,19]}"
      export ATUIN_SHLVL=$SHLVL
    }
  fi
  _cached_eval atuin atuin init zsh --disable-up-arrow
  bindkey '^r' atuin-search
fi

if type "babysit" > /dev/null; then
  alias b="babysit"
  _cached_eval babysit babysit config zsh
fi

if type "goal" > /dev/null; then
  _cached_eval goal goal config zsh
fi

if type "box" > /dev/null; then
  _cached_eval box box config zsh
  # The layer strategy (APFS disk image clones) is macOS-only.
  [[ $OSTYPE == darwin* ]] && export BOX_STRATEGY=layer
  # Skip fetching sources on `box workspace add`; refresh with `box workspace update`.
  export BOX_UPDATE=no
fi

# Google Cloud SDK: add its bin/ to PATH and load completions. Homebrew installs
# the SDK under $HOMEBREW_PREFIX/share (HOMEBREW_PREFIX is exported by the
# `brew shellenv` above), and ships path.zsh.inc / completion.zsh.inc for this.
# The bin/ dir holds gke-gcloud-auth-plugin, which kubectl needs to authenticate
# to GKE clusters — without it on PATH, `kubectl` fails against GKE.
if [[ -n "$HOMEBREW_PREFIX" && -d "$HOMEBREW_PREFIX/share/google-cloud-sdk" ]]; then
  source "$HOMEBREW_PREFIX/share/google-cloud-sdk/path.zsh.inc"
  source "$HOMEBREW_PREFIX/share/google-cloud-sdk/completion.zsh.inc"
fi

# Restore user-local priority after the gcloud include, and drop duplicate
# entries (nested shells inherit an already-populated PATH).
_prefer_user_paths
unfunction _prefer_user_paths
typeset -U path PATH

# Must follow every integration that installs ZLE widgets or hooks.
_load_plugin zsh-users/zsh-syntax-highlighting
