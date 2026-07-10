__proj_ps1() {
  local out=""
  [ -n "$PROJECT_ACTIVE" ] && out+="\[\033[36m\]($PROJECT_ACTIVE)\[\033[00m\] "
  [ -n "$FEATURE_ACTIVE" ] && out+="\[\033[35m\][$FEATURE_ACTIVE]\[\033[00m\] "
  printf '%s' "$out"
}

export FEATURES_CATALOG="${PROJECTS_DIR:-$HOME/projects}/.features.catalog"
export FEATURE_ACTIVE_FILE="${PROJECTS_DIR:-$HOME/projects}/.feature.active"
export FEATURE_ACTIVE=""
[ -f "$FEATURE_ACTIVE_FILE" ] && FEATURE_ACTIVE="$(cat "$FEATURE_ACTIVE_FILE" 2>/dev/null)"

_feat_rows() {
  [ -f "$FEATURES_CATALOG" ] || return 0
  grep -v '^[[:space:]]*#' "$FEATURES_CATALOG" 2>/dev/null \
  | grep -v '^[[:space:]]*$' \
  | awk -F'|' '{ for(i=1;i<=NF;i++){gsub(/^[ \t]+|[ \t]+$/,"",$i)} \
                 if($1!="" && $3!="") print $1"|"$2"|"$3 }'
}

_feat_ids()   { _feat_rows | cut -d'|' -f1 | sort -u; }
_feat_paths() { _feat_rows | awk -F'|' -v f="$1" '$1==f { print "'"$PROJECTS_DIR"'/"$3 }'; }
_feat_branch(){ printf 'feature/%s' "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"; }
_feat_wt_clean() { [ -z "$(git -C "$1" status --porcelain 2>/dev/null)" ]; }

feat() {
  local sub="$1"; shift 2>/dev/null
  case "$sub" in
    create )
      local active_project="$1" jira="$2"
      [ -z "$active_project" ] || [ -z "$jira" ] && { echo "usage: feat create <active_project> <jira-id>"; return 1; }
      _project_names | grep -qx "$active_project" || { echo "project '$active_project' not found (see: project ls)"; return 1; }
      local branch; branch="$(_feat_branch "$jira")"

      # multiple selection using fzf (Tab selects multiple)
      local selection
      if command -v fzf >/dev/null 2>&1; then
        selection=$(_project_pieces "$active_project" \
              | fzf --multi --with-nth=1 --delimiter='\t' \
                    --prompt="$active_project repos (Tab to select)> " \
                    --preview 'ls -la "$(echo {} | cut -f2)" 2>/dev/null') || return
      else
        echo "no fzf: using all repos in project '$active_project'."
        selection=$(_project_pieces "$active_project")
      fi
      [ -z "$selection" ] && { echo "nothing selected."; return 1; }

      # registers in catalog + creates branch in each repo
      cp "$FEATURES_CATALOG" "$FEATURES_CATALOG.bak" 2>/dev/null || true
      local role path rel
      while IFS=$'\t' read -r role path; do
        [ -z "$path" ] && continue
        rel="${path#$PROJECTS_DIR/}"
        printf '%s | %s | %s\n' "$jira" "$active_project" "$rel" >> "$FEATURES_CATALOG"
        echo "── $role ($rel)"
        if [ ! -d "$path/.git" ]; then echo "   is not a git repo, skipped."; continue; fi
        if ! _feat_wt_clean "$path"; then
          echo "   working tree with work in progress, skipped. Resolve it and then run 'feat switch $jira'."
          continue
        fi
        git -C "$path" fetch --all -q
        git -C "$path" checkout -q develop 2>/dev/null || { echo "   no develop branch, skipped."; continue; }
        git -C "$path" branch -D "$branch" 2>/dev/null
        git -C "$path" checkout -q -b "$branch" && echo "   ✓ $branch created"
      done <<< "$selection"

      printf '%s' "$jira" > "$FEATURE_ACTIVE_FILE"; FEATURE_ACTIVE="$jira"
      echo "→ active feature: $jira ($branch)"
      ;;

    switch|use )
      local jira="$1"
      [ -z "$jira" ] && { echo "usage: feat switch <jira-id>"; return 1; }
      _feat_ids | grep -qx "$jira" || { echo "feature '$jira' not found (see: feat ls)"; return 1; }
      local branch; branch="$(_feat_branch "$jira")"

      # first time: validates all repositories before starting
      local dirty=0 p
      while read -r p; do
        [ -d "$p/.git" ] || continue
        if ! _feat_wt_clean "$p"; then
          echo "   dirty: ${p#$PROJECTS_DIR/}"; dirty=1
        fi
      done < <(_feat_paths "$jira")
      if [ "$dirty" -eq 1 ]; then
        echo "aborted: there is at least one dirty repository. Resolve it and try again."
        return 1
      fi

      # second time: now actually switch all repositories
      while read -r p; do
        [ -d "$p/.git" ] || continue
        if git -C "$p" checkout -q "$branch" 2>/dev/null; then
          echo "   ✓ ${p#$PROJECTS_DIR/} -> $branch"
        else
          echo "   ${p#$PROJECTS_DIR/}: branch $branch not found (create with 'feat create')."
        fi
      done < <(_feat_paths "$jira")

      printf '%s' "$jira" > "$FEATURE_ACTIVE_FILE"; FEATURE_ACTIVE="$jira"
      echo "→ active feature: $jira"
      ;;

    cd )
      [ -z "$FEATURE_ACTIVE" ] && { echo "no active feature. run: feat switch <jira-id>"; return 1; }
      local line path
      if command -v fzf >/dev/null 2>&1; then
        line=$(_feat_rows | awk -F'|' -v f="$FEATURE_ACTIVE" '$1==f{print $3}' \
               | fzf --query="$1" --select-1 --exit-0 \
                     --preview 'ls -la "'"$PROJECTS_DIR"'/{}" 2>/dev/null') || return
        path="$PROJECTS_DIR/$line"
      else
        path=$(_feat_paths "$FEATURE_ACTIVE" | grep -i "${1:-.}" | head -1)
      fi
      [ -n "$path" ] && cd "$path" && pwd
      ;;

    ls )
      if [ -n "$1" ]; then
        echo "feature repos $1:"
        _feat_rows | awk -F'|' -v f="$1" '$1==f { printf "  %s\n", $3 }'
      else
        _feat_ids
      fi
      ;;

    which )
      [ -z "$FEATURE_ACTIVE" ] && { echo "no active feature."; return; }
      echo "active feature: $FEATURE_ACTIVE  (branch: $(_feat_branch "$FEATURE_ACTIVE"))"
      _feat_rows | awk -F'|' -v f="$FEATURE_ACTIVE" '$1==f { printf "  %s\n", $3 }'
      ;;

    status )
      local target="${1:-$FEATURE_ACTIVE}"
      [ -z "$target" ] && { echo "usage: feat status [<jira-id>]"; return 1; }
      echo "feature status $target:"
      local p rel br st
      while read -r p; do
        [ -d "$p/.git" ] || { echo "  (non-git) ${p#$PROJECTS_DIR/}"; continue; }
        rel="${p#$PROJECTS_DIR/}"
        br=$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null)
        _feat_wt_clean "$p" && st="clean" || st="dirty"
        printf '  %-40s %-22s %s\n' "$rel" "$br" "$st"
      done < <(_feat_paths "$target")
      ;;

    finish|end )
      local jira="${1:-$FEATURE_ACTIVE}"
      [ -z "$jira" ] && { echo "usage: feat finish [<jira-id>]"; return 1; }
      _feat_ids | grep -qx "$jira" || { echo "feature '$jira' not found."; return 1; }
      local branch; branch="$(_feat_branch "$jira")"
      echo "finishing feature $jira ($branch)..."
      local p rel
      while read -r p; do
        [ -d "$p/.git" ] || continue
        rel="${p#$PROJECTS_DIR/}"
        # exits the branch before trying to delete
        git -C "$p" checkout -q develop 2>/dev/null
        git -C "$p" fetch --all -q
        if git -C "$p" show-ref --verify --quiet "refs/heads/$branch"; then
          if git -C "$p" branch --merged develop | grep -q " *$branch\$"; then
            git -C "$p" branch -d "$branch" -q && echo "   ✓ $rel: merged branch deleted"
          else
            echo "   $rel: '$branch' not merged — kept (delete manually if desired)."
          fi
        else
          echo "   · $rel: with no branch (nothing to delete), develop updated"
        fi
      done < <(_feat_paths "$jira")

      # removes feature from catalog
      cp "$FEATURES_CATALOG" "$FEATURES_CATALOG.bak" 2>/dev/null || true
      awk -F'|' -v f="$jira" '{ t=$1; gsub(/^[ \t]+|[ \t]+$/,"",t); if(t!=f) print }' \
        "$FEATURES_CATALOG.bak" > "$FEATURES_CATALOG" 2>/dev/null
      [ "$FEATURE_ACTIVE" = "$jira" ] && { FEATURE_ACTIVE=""; : > "$FEATURE_ACTIVE_FILE"; }
      echo "→ feature $jira finished. develop updated in repos."
      ;;

    * )
      echo "feat: subcommand: create, switch, cd, ls, which, status, finish"
      [ -n "$FEATURE_ACTIVE" ] && echo "active feature: $FEATURE_ACTIVE"
      ;;
  esac
}
