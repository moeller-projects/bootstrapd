#!/usr/bin/env bash
# lib/rollback.sh — register and replay file-restore actions.
# Deps: log, fs.
set -Eeuo pipefail

_ROLLBACK_REGISTRY="${BOOTSTRAP_STATE:-/tmp}/rollback.tsv"

# register_rollback TARGET COMMAND_STRING
# TARGET is a free-form label. COMMAND_STRING may contain the literal token <backup>
# which the runner substitutes with the path to the most recent backup of TARGET.
register_rollback()
{
  local target="$1" cmd="$2"
  if [[ -z "${BOOTSTRAP_STATE:-}" ]]; then
    return 0
  fi
  mkdir -p "$BOOTSTRAP_STATE"
  local ts
  ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  printf '%s\t%s\t%s\n' "$ts" "$target" "$cmd" >>"$_ROLLBACK_REGISTRY"
  log_debug "rollback registered: $target"
}

# replay_rollback MODULE  — execute every registered action for the given module
# in reverse order. If MODULE is empty, replay everything.
replay_rollback()
{
  local module="${1:-}"
  [[ -f "$_ROLLBACK_REGISTRY" ]] || {
    log_warn "no rollback registry"
    return 0
  }

  # Print the registry in reverse, filtering by module when given.
  local ts target cmd
  tac "$_ROLLBACK_REGISTRY" | while IFS=$'\t' read -r ts target cmd; do
    if [[ -n "$module" && "$target" != *"$module"* ]]; then
      continue
    fi
    # Resolve <backup> by finding the latest backup that matches target basename.
    local bk
    bk="$(fs_find_latest_backup_for "$target")"
    local resolved="${cmd//<backup>/$bk}"
    log_info "rolling back: $target"
    if ((BOOTSTRAP_DRY_RUN)); then
      log_info "would: $resolved"
      continue
    fi
    if ! eval "$resolved" 2>/dev/null; then
      log_warn "rollback step failed (continuing): $target"
    fi
  done
}

# Find the most recent backup for a target. Echoes the path or empty.
fs_find_latest_backup_for()
{
  local target="$1"
  local bn
  bn="$(basename -- "$target")"
  [[ -d "$BOOTSTRAP_STATE/backups" ]] || return 0
  # Each backup is at $BOOTSTRAP_STATE/backups/<sha1>/<bn>.<ts>
  find "$BOOTSTRAP_STATE/backups" -type f -name "${bn}.*" 2>/dev/null |
    sort -r |
    head -1
}

bootstrap_rollback_clear()
{
  rm -f -- "$_ROLLBACK_REGISTRY"
}
