#!/usr/bin/env bash
# lib/log.sh — colored terminal output + persistent log file.
# Deps: none. Globals expected: BOOTSTRAP_STATE, BOOTSTRAP_VERBOSE, BOOTSTRAP_DEBUG.
set -Eeuo pipefail

_LOG_COLORS=1
[[ -t 2 ]] || _LOG_COLORS=0

_log_color()
{
  local code="$1"
  ((_LOG_COLORS)) || return 0
  printf '\033[%sm' "$code"
}

_log_reset()
{
  ((_LOG_COLORS)) || return 0
  printf '\033[0m'
}

_log_now()
{
  date -u +'%Y-%m-%dT%H:%M:%SZ'
}

_log_emit()
{
  local level="$1" color="$2" stream="$3"
  shift 3
  local msg="$*"
  local ts
  ts="$(_log_now)"
  # File
  if [[ -n "${BOOTSTRAP_STATE:-}" ]]; then
    mkdir -p "$BOOTSTRAP_STATE"
    printf '%s\t%s\t%s\n' "$ts" "$level" "$msg" >>"$BOOTSTRAP_STATE/bootstrap.log"
  fi
  # Terminal
  if [[ "$stream" == "stderr" ]]; then
    _log_color "$color" >&2
    printf '%s [%s] %s\n' "$ts" "$level" "$msg" >&2
    _log_reset >&2
  else
    _log_color "$color"
    printf '%s [%s] %s\n' "$ts" "$level" "$msg"
    _log_reset
  fi
}

log_info()
{
  ((BOOTSTRAP_VERBOSE)) && _log_emit INFO "36" stdout "$@" || true
}
log_warn()
{
  _log_emit WARN "33" stderr "$@"
}
log_error()
{
  _log_emit ERROR "31" stderr "$@"
}
log_success()
{
  _log_emit SUCCESS "32" stdout "$@"
}
log_debug()
{
  ((BOOTSTRAP_DEBUG)) && _log_emit DEBUG "90" stdout "$@" || true
}

# Always printed regardless of --verbose. Used for stage transitions and final summary.
log_step()
{
  _log_emit STEP "1;34" stdout "$@"
}
log_done()
{
  _log_emit DONE "1;32" stdout "$@"
}

die()
{
  log_error "$@"
  exit 1
}

trap_error()
{
  local rc=$?
  local cmd="${BASH_COMMAND:-?}"
  log_error "command failed (rc=$rc): $cmd"
}

bootstrap_log_init()
{
  if [[ -n "${BOOTSTRAP_STATE:-}" ]]; then
    mkdir -p "$BOOTSTRAP_STATE"
    : >>"$BOOTSTRAP_STATE/bootstrap.log"
  fi
}
