# Setup fzf function
# ------------------
if [[ ! -x $(whence -p fzf) ]]; then
  unalias fzf 2> /dev/null
  fzf() {
    $FZF_RUBY_EXEC --disable-gems $HOME/.fzf/fzf "$@"
  }
fi
[[ -z $FZF_DEFAULT_OPTS ]] && export FZF_DEFAULT_OPTS="+c -m"

__fzfcmd() {
  (( ${FZF_TMUX:-$+commands[fzf-tmux]} )) && echo "fzf-tmux -d${FZF_TMUX_HEIGHT:-40%}" || echo "fzf"
}

# Key bindings
# ------------
# CTRL-T - Paste the selected file path(s) into the command line
__fsel() {
  local cmd
  if [[ -n $FZF_CTRL_T_COMMAND ]]; then
    cmd=$FZF_CTRL_T_COMMAND
  elif (( $+commands[ag] )); then
    cmd='command ag -g ""'
  else
    cmd="command find -L . \\( -path '*/\\.*' -o -fstype 'dev' -o -fstype 'proc' \\) -prune \
    -o -type f -print \
    -o -type d -print \
    -o -type l -print 2> /dev/null | sed 1d | cut -b3-"
  fi
  eval "$cmd" | $(__fzfcmd) -m | while read item; do
    echo -n "${(q)item} "
  done
  echo
}

# Recent files from neomru
zmodload zsh/mapfile
__neomru() {
  set -o nonomatch
  echo ${(F)${(fOa)mapfile[$HOME/.cache/neomru/file]}[1,-2]} \
    2> /dev/null | $(__fzfcmd) -m +s | while read item; do
    echo -n "${(q)item} "
  done
  echo
}

# List newest files in current directory
__lsfiles() {
  command ls -1Fr --sort=time 2> /dev/null | $(__fzfcmd) --no-sort --multi | \
    while read item; do; echo -n "${(q)item} "; done
  echo
}

if [[ $- =~ i ]]; then

fzf-file-widget() {
  LBUFFER="${LBUFFER}$(__fsel)"
  zle redisplay
}
zle     -N   fzf-file-widget
# bindkey '^T' fzf-file-widget

_add_recent_dir() {
  if (( $chpwd_functions[(I)chpwd_recent_dirs] )); then
    autoload -Uz chpwd_recent_filehandler chpwd_recent_add
    local -aU reply
    chpwd_recent_filehandler
    if [[ $reply[1] != $PWD ]]; then
      chpwd_recent_add $PWD && chpwd_recent_filehandler $reply
    fi
  fi
}

# ALT-C - cd into the selected directory
fzf-cd-widget() {
  cd "${$(set -o nonomatch; command find * -path '*/\.*' -prune \
          -o -type d -print 2> /dev/null | fzf):-.}"
  _add_recent_dir
  zle reset-prompt
}
zle     -N    fzf-cd-widget
bindkey 'ã' fzf-cd-widget  # <M-c>

# CTRL-R - Paste the selected command from history into the command line
fzf-history-widget() {
  newbuffer=$(fc -l -${FZF_HIST_LIMIT:-5000} \
    | LC_ALL='C' sort -k 2 -r                \
    | LC_ALL='C' uniq -f 1                   \
    | LC_ALL='C' sort -n                     \
    | fzf +s +m -n..,1,2..)
  if [[ -n $newbuffer ]]; then
    BUFFER=
    zle vi-fetch-history -n ${newbuffer[(w)1]%%\*}
  fi
  zle redisplay
}
zle     -N   fzf-history-widget
# bindkey '^R' fzf-history-widget

# ALT-R - Paste the selected command from directory history into the command line
fzf-dir-history-widget() {
  newbuffer=$(dirhist $PWD | fzf +s +m)
  lines=(${(s:\\n:)newbuffer})
  if [[ ${#lines} -eq 1 ]]; then
    LBUFFER=$newbuffer
  else
    for line in ${lines[1,-2]}; do
      LBUFFER=${LBUFFER}${line}
      zle vi-open-line-below
    done
    LBUFFER=${LBUFFER}${lines[-1]}
  fi
  zle redisplay
}
zle     -N           fzf-dir-history-widget
bindkey -M viins 'ò' fzf-dir-history-widget  # <M-r>

fzf-combined-widget() {
  if [[ -z $BUFFER ]]; then
    zle fzf-history-widget
  else
    zle fzf-file-widget
  fi
}
zle     -N   fzf-combined-widget
bindkey '^R' fzf-combined-widget

# ALT-D - cd into recent directory
fzf-recent-directory-widget() {
  # Read file $HOME/.chpwd-recent-dirs removing one level of quoting, remove
  # the line with $PWD, then combine into one directory per line of text
  local dir="$(echo ${(F)${${(fOaQ)mapfile[$HOME/.chpwd-recent-dirs]}/#%$PWD}} | fzf +s)"
  if [[ $WIDGET == fzf-recent-directory-widget ]]; then
    cd ${dir:-.}
    _add_recent_dir
  elif [[ -n $dir ]]; then
    LBUFFER=$LBUFFER${(q)dir}
  fi
  zle reset-prompt
}
zle     -N  fzf-recent-directory-widget
bindkey 'ä' fzf-recent-directory-widget  # <M-d>
zle     -N  fzf-recent-directory-insert-widget
bindkey 'Ä' fzf-recent-directory-insert-widget  # <M-D>

# ALT-D - open file from neomru
fzf-neomru-widget() {
  LBUFFER="${LBUFFER}$(__neomru)"
  zle redisplay
}
zle     -N   fzf-neomru-widget
bindkey '^Y' fzf-neomru-widget

# CTRL-X CTRL-F - open files in current directory
fzf-lsfiles-widget() {
  LBUFFER="${LBUFFER}$(__lsfiles)"
  zle redisplay
}
zle     -N     fzf-lsfiles-widget
bindkey '^X^F' fzf-lsfiles-widget

fzf-alt-combined-widget() {
  if [[ -z $BUFFER ]]; then
    zle fzf-dir-history-widget
  else
    zle fzf-neomru-widget
  fi
}
zle     -N  fzf-alt-combined-widget
bindkey 'ò' fzf-alt-combined-widget  # <M-r>

fzf-all-history-widget() {
  FZF_HIST_LIMIT=$HISTSIZE zle fzf-history-widget
}
zle     -N  fzf-all-history-widget
bindkey 'Ò' fzf-all-history-widget  # <M-R>

fzf-window-words-widget() {
  local result=$( tmux list-panes -F '#{pane_id}' |
  xargs -n1 tmux capture-pane -p -t |
  command sed -e 'p;s/[^a-zA-Z0-9_]/ /g' |
  command tr -s '[:space:]' '\n' |
  command grep -o '\S.\+\S' |
  LC_ALL='C' awk '{ print length(), $0 | "sort -n" }' |
  LC_ALL='C' awk '{ print $2 }' |
  LC_ALL='C' uniq |
  fzf --no-sort --multi )
  LBUFFER=${LBUFFER}${(j: :)${(f)result}}
  zle redisplay
}
zle     -N     fzf-window-words-widget
bindkey '^X^W' fzf-window-words-widget

source ${0:A:h}/shell/completion.zsh

fi
