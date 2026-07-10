export LANG=en_US.UTF-8
export PROMPT_COMMAND='__git_ps1 "\[\033[33m\]\w\[\033[31m\]" "\[\033[00m\]\$ "'
# export TERM=xterm.256color

export HISTSIZE=10000
export HISTFILESIZE=20000

# OTIMIZADO: ignoreboth = ignoredups + ignorespace.
#   -> continua removendo duplicatas consecutivas (como antes)
#   -> AGORA: um comando iniciado com espaço NÃO vai pro histórico
#      (útil p/ comandos com token/senha). 'erasedups' mantido.
export HISTCONTROL=ignoreboth:erasedups

export HISTTIMEFORMAT="%y-%m-%d %T "     # timestamps nos comandos (PRESERVADO)
shopt -s histappend                      # append em vez de sobrescrever (PRESERVADO)

# OTIMIZADO: segurança e fidelidade do histórico
shopt -s histverify   # expansão (!!, !$) é mostrada antes de executar
shopt -s cmdhist      # comandos multilinha viram uma entrada só
shopt -s lithist      # ...preservando as quebras de linha originais


# ============================================================================
# [3] OPÇÕES DE SHELL
# ============================================================================
# OTIMIZADO / NOVO: qualidade de vida na navegação
shopt -s autocd       # digitar o caminho já faz 'cd' (ex.: ~/projects/jq9)
shopt -s cdspell      # corrige pequenos typos em 'cd'
shopt -s dirspell     # corrige typos em nomes de diretório no tab-complete
shopt -s direxpand    # expande variáveis em paths ao dar tab
shopt -s globstar     # habilita ** recursivo (essencial p/ FZF e busca)
shopt -s nocaseglob   # glob case-insensitive (conveniente no Windows/Cygwin)
shopt -s checkwinsize # reavalia LINES/COLUMNS após cada comando


# ============================================================================
# [4] KEYBINDINGS + COMPLETION
# ============================================================================
# PRESERVADO: busca no histórico pelas setas ao digitar
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'
bind '"\C-l": clear-screen'          # Ctrl+L limpa a tela
bind '"\C-u": unix-line-discard'     # Ctrl+U apaga a linha (corrigido: unix-line-discard)
bind '"\C-w": backward-kill-word'    # Ctrl+W apaga a última palavra

# completion (OTIMIZADO: guardas [ -f ] p/ não gerar erro se faltar)
[ -f ~/tools/git-completion.bash ] && source ~/tools/git-completion.bash
bind 'set show-all-if-ambiguous on'
bind 'set completion-ignore-case on' # tab-complete case-insensitive

# BUG CORRIGIDO: '~' entre aspas NÃO expande -> o teste antigo sempre falhava
# e o compat nunca era carregado. Usar $HOME resolve.
if [ -f "$HOME/tools/bash_completion.d/000_bash_completion_compat.bash" ]; then
  . "$HOME/tools/bash_completion.d/000_bash_completion_compat.bash"
fi


# ============================================================================
# [5] NAVEGAÇÃO
# ============================================================================
# NOVO: 'cd jq9' resolve a partir de ~/projects de qualquer lugar
export CDPATH=".:$HOME/projects"

# PRESERVADO
alias n-jq9='cd ~/projects/jq9/ && ls'

# global aliases (PRESERVADO)
alias ll='ls -lah --color=auto'
alias mkd='mkdir -p'
alias e='explorer.exe .'


# ============================================================================
# [6] GIT ALIASES  —  PRESERVADOS INTEGRALMENTE (não alterar)
# ----------------------------------------------------------------------------
#  ATENÇÃO: 'gs' está definido 2x (status e stash). O último vence,
#  então hoje  gs = git stash. Mantido exatamente como no original;
#  decisão sua se quiser renomear um deles.
# ============================================================================
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


# ============================================================================
# [7] INFRA / PYTHON / AWS  (PRESERVADO)
# ============================================================================
# bastion
alias bastion='~/projects/itau-jq9-infra-vm-ec2/scripts/start_session_manager_port_forwarding.sh'

# pip install
alias pi='cd src && PYTHON_MINOR_VERSION=$(../venv/Scripts/python -c "import sys; print(sys.version_info.minor)") && ../venv/Scripts/pip3.$PYTHON_MINOR_VERSION install -r ./requirements.txt && cd ..'
alias pti='cd app && PYTHON_MINOR_VERSION=$(../venv/Scripts/python -c "import sys; print(sys.version_info.minor)") && ../venv/Scripts/pip3.$PYTHON_MINOR_VERSION install -r ./tests/test_requirements.txt && cd ..'
alias ptin='cd app && PYTHON_MINOR_VERSION=$(../venv/Scripts/python -c "import sys; print(sys.version_info.minor)") && ../venv/Scripts/pip3.$PYTHON_MINOR_VERSION install -r ./requirements-tests.txt && cd ..'

# aws cli
alias aws-dev="aws sso login --no-verify-ssl --profile DEVELOPER_ACCESS-875075923542"


# ============================================================================
# [8] FZF — INTEGRAÇÃO E PRODUTIVIDADE  (só o binário ~/tools/fzf.exe)
# ----------------------------------------------------------------------------
#  Você tem APENAS o fzf.exe, sem os scripts key-bindings.bash /
#  completion.bash. Tudo aqui usa só o binário + ferramentas nativas do
#  Cygwin/Git Bash (find, grep, sed, cut, git, cat, cygpath, explorer.exe).
#  Ctrl-R e Ctrl-T são implementados MANUALMENTE via 'bind -x'.
# ============================================================================
export PROJECTS_DIR="$HOME/projects"

# --- Localiza o fzf.exe e o coloca no PATH ----------------------------------
export FZF_EXE="$HOME/tools/fzf.exe"
if [ -x "$FZF_EXE" ]; then
  # Garante que 'fzf' funcione como comando solto também
  case ":$PATH:" in *":$HOME/tools:"*) ;; *) export PATH="$HOME/tools:$PATH";; esac
  # Wrapper: normaliza a saída (remove \r do Windows) em todas as chamadas
  fzf() { "$FZF_EXE" "$@" | sed 's/\r$//'; }

  # Aparência padrão aplicada a toda invocação do fzf
  export FZF_DEFAULT_OPTS='--height 45% --layout=reverse --border --info=inline --cycle'

  # --------------------------------------------------------------------------
  #  p [filtro] — pula para qualquer repo de microserviço via fzf
  #  Varre ~/projects/<sigla>/<tipo> (apps|infra|gateway|tests) e a <sigla>.
  #  Uso:  p | p gate | p jq9/infra
  # --------------------------------------------------------------------------
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

  # --------------------------------------------------------------------------
  #  ff [filtro] — busca ARQUIVO (recursivo, sem .git) com preview; abre editor
  # --------------------------------------------------------------------------
  ff() {
    local file
    file=$(
      find . -type f -not -path '*/.git/*' 2>/dev/null | sed 's|^\./||' \
      | fzf --query="$1" --select-1 --exit-0 \
            --preview 'cat -n {} 2>/dev/null | head -200'
    ) || return
    [ -n "$file" ] && "${EDITOR:-vi}" "$file"
  }

  # --------------------------------------------------------------------------
  #  fcd [filtro] — vai para o DIRETÓRIO de um arquivo escolhido
  # --------------------------------------------------------------------------
  fcd() {
    local file
    file=$(
      find . -type f -not -path '*/.git/*' 2>/dev/null | sed 's|^\./||' \
      | fzf --query="$1" --select-1 --exit-0
    ) || return
    [ -n "$file" ] && cd "$(dirname "$file")" && pwd
  }

  # --------------------------------------------------------------------------
  #  frg <termo> — busca por CONTEÚDO via grep -rn nativo + preview da linha
  #  Uso:  frg TransactionService   -> abre o arquivo na linha encontrada
  # --------------------------------------------------------------------------
  frg() {
    [ -z "$1" ] && { echo "uso: frg <termo>"; return 1; }
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

  # --------------------------------------------------------------------------
  #  gcof [filtro] — checkout de BRANCH via fzf (local + remota)
  #  Complementa seus aliases git sem alterá-los.
  # --------------------------------------------------------------------------
  gcof() {
    local branch
    branch=$(
      git branch --all 2>/dev/null \
      | grep -v HEAD | sed 's|remotes/origin/||;s/^[* ]*//' \
      | sort -u | fzf --query="$1" --select-1 --exit-0
    ) || return
    [ -n "$branch" ] && git checkout "$branch"
  }

  # --------------------------------------------------------------------------
  #  fe [filtro] — escolhe arquivo/pasta e abre no EXPLORER do Windows
  #  Usa cygpath p/ converter /home/... em C:\... (ponte Cygwin->Windows)
  # --------------------------------------------------------------------------
  fe() {
    local item
    item=$(
      find . -not -path '*/.git/*' 2>/dev/null | sed 's|^\./||' \
      | fzf --query="$1" --select-1 --exit-0
    ) || return
    [ -n "$item" ] && explorer.exe "$(cygpath -w "$item")"
  }

  # ==========================================================================
  #  KEYBINDINGS via 'bind -x' — implementação manual, sem scripts do fzf.
  #  Substituem a linha de comando usando READLINE_LINE / READLINE_POINT.
  # ==========================================================================

  # --- Ctrl-R : histórico fuzzy (troca o reverse-search default) ------------
  #  Mantém suas setas ↑/↓ (history-search) intactas da seção [4].
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

  # --- Ctrl-T : insere ARQUIVO escolhido na linha de comando atual ----------
  #  Ex.: digite  vim <Ctrl-T>  e escolha o arquivo; ele é colado no cursor.
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

  # --- Alt-C : cd fuzzy para um subdiretório (nativo, sem script fzf) --------
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
# ============================================================================
