#!/usr/bin/env bash
# lib/templates.sh — envsubst-style template rendering.
# Templates may reference ${VAR} or $VAR. Unknown vars become empty.
# Deps: log, fs.
set -Eeuo pipefail

# Pure-Bash ${VAR}/${VAR:-default}/$VAR substitution.
# Mirrors the subset of envsubst that we actually use.
_tpl_subst()
{
  local line="$1"
  local result="$line"
  local brace_re='\$\{[A-Za-z_][A-Za-z0-9_]*(:[+-]?[^}]*)?\}'
  local bare_re='(^|[^A-Za-z0-9_])\$[A-Za-z_][A-Za-z0-9_]*'
  # First pass: ${VAR...} forms.
  while [[ "$result" =~ $brace_re ]]; do
    local match="${BASH_REMATCH[0]}"
    local name="${match#\${}"
    name="${name%\}}"
    # Strip the operator suffix (e.g. :-default, -default, :+alt, +alt).
    case "$name" in
      *:*) name="${name%%:*}" ;;
    esac
    local op="${match#\${$name}}"
    op="${op%\}}"
    local value="${!name:-}"
    local replacement=""
    case "$op" in
      "") replacement="$value" ;;
      :-*) [[ -z "$value" ]] && replacement="${op#:-}" || replacement="$value" ;;
      -*) [[ -z "$value" ]] && replacement="${op#-}" || replacement="$value" ;;
      :+*) [[ -n "$value" ]] && replacement="${op#:+}" || replacement="" ;;
      *) replacement="$value" ;;
    esac
    result="${result//$match/$replacement}"
  done
  # Second pass: bare $NAME.
  while [[ "$result" =~ $bare_re ]]; do
    local pre="${BASH_REMATCH[1]}"
    local ref="${BASH_REMATCH[0]#"$pre"}"
    local name="${ref#\$}"
    local value="${!name:-}"
    result="${result//$ref/$value}"
  done
  printf '%s' "$result"
}

# tpl_render STRING  → expanded string with current shell env.
tpl_render()
{
  local template="$1"
  if command -v envsubst >/dev/null 2>&1; then
    envsubst <<<"$template"
    return 0
  fi
  local line out=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    out+="$(_tpl_subst "$line")"$'\n'
  done <<<"$template"
  printf '%s' "${out%$'\n'}"
}

# tpl_render_file SRC DEST [mode]  — reads SRC, renders, writes atomically.
tpl_render_file()
{
  local src="$1" dest="$2" mode="${3:-0644}"
  if [[ ! -r "$src" ]]; then
    log_error "template not readable: $src"
    return 1
  fi
  local rendered
  rendered="$(tpl_render "$(cat -- "$src")")"
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would render $src -> $dest (mode $mode)"
    return 0
  fi
  fs_backup_file "$dest" >/dev/null || true
  local dir tmp
  dir="$(dirname -- "$dest")"
  fs_mkdir_p "$dir"
  tmp="$(mktemp "$dir/.bootstrapx.XXXXXX")"
  printf '%s' "$rendered" >"$tmp"
  chmod "$mode" "$tmp"
  mv -f -- "$tmp" "$dest"
  register_rollback "$dest" "fs_restore_backup <backup> $dest"
}
