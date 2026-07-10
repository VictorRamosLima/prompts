export LANG=en_US.UTF-8
export PROMPT_COMMAND='__git_ps1 "\[\033[33m\]\w\[\033[31m\]" "\[\033[00m\]\$ "'
# export TERM=xterm.256color

export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth:erasedups
export HISTTIMEFORMAT="%y-%m-%d %T "     # timestamps on commands
shopt -s histappend                      # append instead of overwriting

# security and fidelity of history
shopt -s histverify   # expansion (!!, !$) is shown before executing
shopt -s cmdhist      # multiline commands become a single entry
shopt -s lithist      # ...preserving original line breaks

# quality of life during navigation
shopt -s autocd       # typing a path does 'cd'
shopt -s cdspell      # corrects typos in 'cd'
shopt -s dirspell     # corrects typos in directory names on tab-complete
shopt -s direxpand    # expands variables in paths on tab-complete
shopt -s globstar     # enables ** recursive (essential for FZF and search)
shopt -s nocaseglob   # glob case-insensitive
shopt -s checkwinsize # re-evaluates LINES/COLUMNS after each command

# search history with arrow keys
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'
bind '"\C-l": clear-screen'          # Ctrl+L erases the screen
bind '"\C-u": unix-line-discard'     # Ctrl+U apaga a linha
bind '"\C-w": backward-kill-word'    # Ctrl+W erases the last word

# git completion
[ -f ~/tools/git-completion.bash ] && source ~/tools/git-completion.bash
bind 'set show-all-if-ambiguous on'
bind 'set completion-ignore-case on' # tab-complete case-insensitive

# bash completions
if [ -f "$HOME/tools/bash_completion.d/000_bash_completion_compat.bash" ]; then
  . "$HOME/tools/bash_completion.d/000_bash_completion_compat.bash"
fi

# 'cd jq9' resolves ~/projects from any place
export CDPATH=".:$HOME/projects"

# global aliases
alias ll='ls -lah --color=auto'
alias mkd='mkdir -p'
alias e='explorer.exe .'

# git aliases
alias gpd='git pull origin develop --rebase --autostash'
alias gca='git commit --amend'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gcd='git checkout develop'
alias gcbf='git checkout -b feature/'
alias gbd='git branch -D'
alias gbdd='git branch -D develop'
alias gbdm='git branch -D main'
alias gpf='git push -f origin $(git rev-parse --abbrev-ref HEAD)'
alias gf='git fetch --all'
alias gu='git reset --soft HEAD^'
alias gs='git status'
alias ga='git add'
alias gaa='git add .'
alias gc='git commit -m'
alias gs='git stash'
alias gsp='git stash pop'
alias gb='git branch'
alias gp='git push origin $(git rev-parse --abbrev-ref HEAD)'

# bastion
alias bastion='~/projects/itau-jq9-infra-vm-ec2/scripts/start_session_manager_port_forwarding.sh'

# pip install
alias pi='cd src && PYTHON_MINOR_VERSION=$(../venv/Scripts/python -c "import sys; print(sys.version_info.minor)") && ../venv/Scripts/pip3.$PYTHON_MINOR_VERSION install -r ./requirements.txt && cd ..'
alias pti='cd app && PYTHON_MINOR_VERSION=$(../venv/Scripts/python -c "import sys; print(sys.version_info.minor)") && ../venv/Scripts/pip3.$PYTHON_MINOR_VERSION install -r ./tests/test_requirements.txt && cd ..'
alias ptin='cd app && PYTHON_MINOR_VERSION=$(../venv/Scripts/python -c "import sys; print(sys.version_info.minor)") && ../venv/Scripts/pip3.$PYTHON_MINOR_VERSION install -r ./requirements-tests.txt && cd ..'

# aws cli
alias aws-dev="aws sso login --no-verify-ssl --profile DEVELOPER_ACCESS-875075923542"

export PROJECTS_DIR="$HOME/projects"

export FZF_EXE="$HOME/tools/fzf.exe"
if [ -x "$FZF_EXE" ]; then
  case ":$PATH:" in *":$HOME/tools:"*) ;; *) export PATH="$HOME/tools:$PATH";; esac
  fzf() { "$FZF_EXE" "$@" | sed 's/\r$//'; }

  export FZF_DEFAULT_OPTS='--height 45% --layout=reverse --border --info=inline --cycle'

  p() {
    local dir
    dir=$(
      find "$PROJECTS_DIR" -mindepth 1 -maxdepth 2 -type d -not -path '*/.git*' 2>/dev/null \
      | sed "s|$PROJECTS_DIR/||" \
      | fzf --query="$1" --select-1 --exit-0 \
            --preview "ls -la '$PROJECTS_DIR'/{} 2>/dev/null" \
            --preview-window=right:50%
    ) || return
    [ -n "$dir" ] && cd "$PROJECTS_DIR/$dir" && ls
  }

  pj() { p "jq9/$1"; }   # ex.: pj apps    -> jq9/apps
  pr() { p "rw9/$1"; }   # ex.: pr gateway -> rw9/gateway

  #  ff [filter]: finds file recursively (excluding .git) with preview; opens editor
  ff() {
    local file
    file=$(
      find . -type f -not -path '*/.git/*' 2>/dev/null | sed 's|^\./||' \
      | fzf --query="$1" --select-1 --exit-0 \
            --preview 'cat -n {} 2>/dev/null | head -200'
    ) || return
    [ -n "$file" ] && "${EDITOR:-vi}" "$file"
  }

  #  fcd [filter] — vai para o DIRETÓRIO de um arquivo escolhido
  fcd() {
    local file
    file=$(
      find . -type f -not -path '*/.git/*' 2>/dev/null | sed 's|^\./||' \
      | fzf --query="$1" --select-1 --exit-0
    ) || return
    [ -n "$file" ] && cd "$(dirname "$file")" && pwd
  }

  #  frg <term>: search for <term> via grep -rn nativo + preview da linha
  #  Usage:  frg TransactionService   -> opens file at line found
  frg() {
    [ -z "$1" ] && { echo "usage: frg <term>"; return 1; }
    local sel
    sel=$(
      grep -rn --binary-files=without-match "$1" . 2>/dev/null \
      | grep -v '/\.git/' \
      | fzf --delimiter=: \
            --preview 'sed -n "$(({2}-3)),$(({2}+3))p" {1} 2>/dev/null' \
            --preview-window=up:7
    ) || return
    [ -n "$sel" ] && "${EDITOR:-vi}" "$(echo "$sel" | cut -d: -f1)" \
                       "+$(echo "$sel" | cut -d: -f2)"
  }

  #  gcof [filter]: checkout BRANCH using fzf (local + remote)
  gcof() {
    local branch
    branch=$(
      git branch --all 2>/dev/null \
      | grep -v HEAD | sed 's|remotes/origin/||;s/^[* ]*//' \
      | sort -u | fzf --query="$1" --select-1 --exit-0
    ) || return
    [ -n "$branch" ] && git checkout "$branch"
  }

  #  fe [filter]: escolhe arquivo/pasta e abre no EXPLORER do Windows
  #  Uses cygpath to convert /home/... to C:\... (Cygwin->Windows path)
  fe() {
    local item
    item=$(
      find . -not -path '*/.git/*' 2>/dev/null | sed 's|^\./||' \
      | fzf --query="$1" --select-1 --exit-0
    ) || return
    [ -n "$item" ] && explorer.exe "$(cygpath -w "$item")"
  }

  # --- Ctrl-R: fuzzy history search (replaces default reverse-search)
  # Keeps ↑/↓ (history-search) intact from section [4].
  __fzf_history() {
    local sel
    sel=$(
      HISTTIMEFORMAT= history \
      | sed 's/^ *[0-9][0-9]*[ *] *//' \
      | awk '!seen[$0]++' \
      | fzf --tac --query="$READLINE_LINE" \
            --prompt='hist> ' --height 45% --layout=reverse
    )
    if [ -n "$sel" ]; then
      READLINE_LINE="$sel"
      READLINE_POINT=${#READLINE_LINE}
    fi
  }
  bind -x '"\C-r": __fzf_history'

  # --- Ctrl-T: inserts chosen file at cursor position in command line
  #  Usage: vim <Ctrl-T>  -> choose file; it is pasted at cursor position
  __fzf_file_widget() {
    local sel
    sel=$(
      find . -type f -not -path '*/.git/*' 2>/dev/null | sed 's|^\./||' \
      | fzf --height 45% --layout=reverse --border
    )
    if [ -n "$sel" ]; then
      READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}$sel${READLINE_LINE:$READLINE_POINT}"
      READLINE_POINT=$(( READLINE_POINT + ${#sel} ))
    fi
  }
  bind -x '"\C-t": __fzf_file_widget'

  # --- Alt-C: cd fuzzy to a subdirectory
  __fzf_cd_widget() {
    local dir
    dir=$(
      find . -type d -not -path '*/.git/*' 2>/dev/null | sed 's|^\./||' \
      | fzf --height 45% --layout=reverse --border
    )
    [ -n "$dir" ] && cd "$dir"
  }
  bind -x '"\ec": __fzf_cd_widget'   # \ec = Alt-C

else
  echo "aviso: fzf.exe não encontrado em $FZF_EXE — funções fzf desativadas" >&2
fi
