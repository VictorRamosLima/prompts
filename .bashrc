# ============================================================================
#  .bashrc — ambiente Cygwin / Bash 5.3.9 (Itaú, microserviços por sigla)
#  Estrutura de projetos: ~/projects/{sigla}/{apps|infra|gateway|tests}
# ----------------------------------------------------------------------------
#  Seções:
#    [1] Locale e prompt              [5] Navegação (CDPATH + aliases)
#    [2] Histórico                    [6] Aliases git (PRESERVADOS)
#    [3] Opções de shell (shopt)      [7] Aliases de projeto/infra/python/aws
#    [4] Keybindings + completion     [8] FZF: integração e funções
# ============================================================================


# ============================================================================
# [1] LOCALE E PROMPT
# ============================================================================
export LANG=en_US.UTF-8

# Prefixo do prompt com o projeto lógico ativo (seção [9]), em ciano.
# Fica vazio quando nenhum projeto está ativo, então o prompt normal não muda.
__proj_ps1() {
  [ -n "$PROJ_ACTIVE" ] && printf '\[\033[36m\](%s)\[\033[00m\] ' "$PROJ_ACTIVE"
}
# __git_ps1 recebe o \w (path) e o sufixo. Prependo o projeto via 1º argumento.
export PROMPT_COMMAND='__git_ps1 "$(__proj_ps1)\[\033[33m\]\w\[\033[31m\]" "\[\033[00m\]\$ "'
# export TERM=xterm.256color


# ============================================================================
# [2] HISTÓRICO  (PRESERVADO + otimizações pontuais)
# ============================================================================
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

# completion (guardas [ -f ] p/ não gerar erro se faltar)
[ -f ~/tools/git-completion.bash ] && source ~/tools/git-completion.bash
bind 'set show-all-if-ambiguous on'
bind 'set completion-ignore-case on' # tab-complete case-insensitive

# --- bash-completion --------------------------------------------------------
# NOTA: você NÃO tem o pacote bash-completion principal instalado — apenas
# peças soltas em ~/tools. O arquivo 000_..._compat.bash é só um SHIM desse
# pacote e, sozinho, ou dá erro (_comp_deprecate_func not found) ou fica
# inerte. Por isso ele foi DELIBERADAMENTE removido daqui: o git-completion
# acima já cobre o completion de git (branches, remotes, subcomandos), que é
# o que realmente importa no seu fluxo.
#
# Se um dia quiser completion completo (docker, aws, kubectl...), instale o
# pacote de verdade e dê source no arquivo principal, ex.:
#   . /usr/share/bash-completion/bash_completion


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

# ============================================================================
# [9] WORKSPACES LÓGICOS POR PROJETO  (namespace sem mexer nas pastas)
# ----------------------------------------------------------------------------
#  Camada LÓGICA sobre a estrutura física ~/projects/{sigla}/{tipo}.
#  Um "projeto de negócio" (ex.: portal-suprimentos) agrega peças espalhadas
#  por várias pastas de tipo (apps, gateway, infra...). Nada é movido no disco.
#
#  Fonte de verdade: ~/.projects.catalog  (texto, versionável, editável à mão)
#  Formato por linha:   projeto | papel | caminho-relativo-a-~/projects
#  Linhas com # são comentários; linhas vazias são ignoradas.
#
#  Comandos:
#    proj                 fzf entre projetos; "entra" no escolhido
#    proj <nome>          entra direto no projeto
#    proj cd [papel]      fzf entre as PEÇAS do projeto ativo -> cd
#    proj ls [nome]       lista projetos, ou peças de um projeto
#    proj add             wizard interativo que anexa peças no catálogo
#    proj rm <nome>       remove um projeto do catálogo (com backup)
#    proj which           mostra projeto ativo e suas peças
#    proj doctor [nome]   verifica se os caminhos do catálogo existem
#    proj edit            abre o catálogo no $EDITOR
#
#  NOTA sobre Go: um binário Go não pode fazer 'cd' no shell pai (fronteira
#  de processo), então a navegação vive no bash de propósito. Se um dia o
#  catálogo precisar de lógica pesada (grafo de dependências, TUI), dá pra
#  escrever um subcomando 'proj graph' em Go e plugá-lo aqui sem reescrever.
# ============================================================================
export PROJECTS_CATALOG="$HOME/.projects.catalog"
export PROJ_ACTIVE=""   # projeto atualmente ativo (aparece no prompt, seção final)

# --- helper interno: emite linhas limpas "projeto|papel|caminho" ------------
_proj_rows() {
  [ -f "$PROJECTS_CATALOG" ] || return 0
  grep -v '^[[:space:]]*#' "$PROJECTS_CATALOG" 2>/dev/null \
  | grep -v '^[[:space:]]*$' \
  | awk -F'|' '{ for(i=1;i<=NF;i++){gsub(/^[ \t]+|[ \t]+$/,"",$i)} \
                 if($1!="" && $3!="") print $1"|"$2"|"$3 }'
}

# --- lista de projetos distintos --------------------------------------------
_proj_names() { _proj_rows | cut -d'|' -f1 | sort -u; }

# --- peças (papel<TAB>caminho-absoluto) de um projeto -----------------------
_proj_pieces() {
  local p="$1"
  _proj_rows | awk -F'|' -v p="$p" '$1==p { print $2"\t""'"$PROJECTS_DIR"'/"$3 }'
}

proj() {
  local sub="$1"; shift 2>/dev/null
  case "$sub" in
    "" )   # sem argumento: fzf entre projetos e entra
      local sel
      if command -v fzf >/dev/null 2>&1; then
        sel=$(_proj_names | fzf --prompt='projeto> ' \
              --preview "awk -F'\\\\|' -v p={} '\$1==p{gsub(/^[ \t]+|[ \t]+\$/,\"\",\$1)} \$0 ~ \"^[[:space:]]*\"p' '$PROJECTS_CATALOG'" \
              --preview-window=right:55%) || return
      else
        _proj_names; echo; printf 'uso: proj <nome>\n'; return
      fi
      [ -n "$sel" ] && proj "$sel"
      ;;
    ls )
      if [ -n "$1" ]; then
        printf 'peças de %s:\n' "$1"
        _proj_pieces "$1" | while IFS=$'\t' read -r papel path; do
          printf '  %-18s %s\n' "$papel" "$path"
        done
      else
        _proj_names
      fi
      ;;
    cd )  # navega entre as peças do projeto ATIVO
      [ -z "$PROJ_ACTIVE" ] && { echo "nenhum projeto ativo. use: proj <nome>"; return 1; }
      local line papel path
      if command -v fzf >/dev/null 2>&1; then
        line=$(_proj_pieces "$PROJ_ACTIVE" | fzf --query="$1" --select-1 --exit-0 \
               --with-nth=1 --delimiter='\t' \
               --preview 'ls -la "$(echo {} | cut -f2)" 2>/dev/null') || return
      else
        line=$(_proj_pieces "$PROJ_ACTIVE" | grep -i "${1:-.}" | head -1)
      fi
      path=$(printf '%s' "$line" | cut -f2)
      [ -n "$path" ] && cd "$path" && pwd
      ;;
    add )  # wizard interativo -> anexa no catálogo
      local proj_name papel caminho
      read -r -p "nome do projeto (ex: portal-suprimentos): " proj_name
      [ -z "$proj_name" ] && { echo "cancelado."; return 1; }
      echo "agora adicione as peças. Enter em 'papel' vazio encerra."
      while true; do
        read -r -p "  papel (ex: lambda-carrinho, bff, front, gateway): " papel
        [ -z "$papel" ] && break
        read -r -p "  caminho relativo a ~/projects (ex: jq9/apps/x): " caminho
        [ -z "$caminho" ] && { echo "  caminho vazio, peça ignorada."; continue; }
        if [ ! -d "$PROJECTS_DIR/$caminho" ]; then
          read -r -p "  ⚠ '$PROJECTS_DIR/$caminho' não existe. Adicionar mesmo assim? [s/N] " ok
          [ "$ok" = "s" ] || [ "$ok" = "S" ] || { echo "  ignorada."; continue; }
        fi
        printf '%s | %s | %s\n' "$proj_name" "$papel" "$caminho" >> "$PROJECTS_CATALOG"
        echo "  + adicionada."
      done
      echo "pronto. veja com: proj ls $proj_name"
      ;;
    rm )
      [ -z "$1" ] && { echo "uso: proj rm <nome>"; return 1; }
      [ -f "$PROJECTS_CATALOG" ] || { echo "catálogo não existe."; return 1; }
      cp "$PROJECTS_CATALOG" "$PROJECTS_CATALOG.bak"
      awk -F'|' -v p="$1" '{ t=$1; gsub(/^[ \t]+|[ \t]+$/,"",t); if(t!=p) print }' \
        "$PROJECTS_CATALOG.bak" > "$PROJECTS_CATALOG"
      echo "removido '$1' (backup em $PROJECTS_CATALOG.bak)"
      [ "$PROJ_ACTIVE" = "$1" ] && PROJ_ACTIVE=""
      ;;
    which )
      [ -z "$PROJ_ACTIVE" ] && { echo "nenhum projeto ativo."; return; }
      printf 'projeto ativo: %s\n' "$PROJ_ACTIVE"
      _proj_pieces "$PROJ_ACTIVE" | while IFS=$'\t' read -r papel path; do
        printf '  %-18s %s\n' "$papel" "$path"
      done
      ;;
    doctor )
      local target="${1:-}"
      local names; names=$( [ -n "$target" ] && echo "$target" || _proj_names )
      local miss=0
      for n in $names; do
        printf '• %s\n' "$n"
        _proj_pieces "$n" | while IFS=$'\t' read -r papel path; do
          if [ -d "$path" ]; then printf '   OK    %s\n' "$papel"
          else printf '   FALTA %s -> %s\n' "$papel" "$path"; fi
        done
      done
      ;;
    edit )
      "${EDITOR:-vi}" "$PROJECTS_CATALOG"
      ;;
    * )  # 'proj <nome>' : ativa o projeto
      if _proj_names | grep -qx "$sub"; then
        PROJ_ACTIVE="$sub"
        echo "→ projeto ativo: $sub"
        # entra na primeira peça do projeto
        local first; first=$(_proj_pieces "$sub" | head -1 | cut -f2)
        [ -n "$first" ] && cd "$first" && pwd
        echo "use 'proj cd' p/ pular entre as peças, 'proj which' p/ ver todas."
      else
        echo "projeto '$sub' não encontrado. Disponíveis:"; _proj_names
        echo "(subcomandos: ls, cd, add, rm, which, doctor, edit)"
      fi
      ;;
  esac
}
# ============================================================================
