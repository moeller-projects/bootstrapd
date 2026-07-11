#!/usr/bin/env bash
# BootstrapX — main entry point.
# See README.md, ARCHITECTURE.md.
set -Eeuo pipefail

BOOTSTRAP_VERSION="0.1.0"
BOOTSTRAP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BOOTSTRAP_ROOT

# Locations
export BOOTSTRAP_LIB="$BOOTSTRAP_ROOT/lib"
export BOOTSTRAP_MODULES="$BOOTSTRAP_ROOT/modules"
export BOOTSTRAP_STATE="$BOOTSTRAP_ROOT/state"
export BOOTSTRAP_TEMPLATES="$BOOTSTRAP_ROOT/templates"
export BOOTSTRAP_FILES="$BOOTSTRAP_ROOT/files"
export BOOTSTRAP_CONFIG="${BOOTSTRAP_CONFIG:-$BOOTSTRAP_ROOT/bootstrap.conf}"
export BOOTSTRAP_LOG_FORMAT="${BOOTSTRAP_LOG_FORMAT:-text}"

# Modes / flags (set by CLI parsing)
BOOTSTRAP_CMD="run"
BOOTSTRAP_DRY_RUN=0
BOOTSTRAP_FORCE=0
BOOTSTRAP_SAFE=1
BOOTSTRAP_VERBOSE=0
BOOTSTRAP_DEBUG=0
BOOTSTRAP_NON_INTERACTIVE=0
BOOTSTRAP_ONLY=""
BOOTSTRAP_STAGE=""
DOCTOR_JSON_OUTPUT=0

# Load libraries in dependency order.
# shellcheck source=lib/system.sh
. "$BOOTSTRAP_LIB/system.sh"
# shellcheck source=lib/log.sh
. "$BOOTSTRAP_LIB/log.sh"
# shellcheck source=lib/fs.sh
. "$BOOTSTRAP_LIB/fs.sh"
# shellcheck source=lib/network.sh
. "$BOOTSTRAP_LIB/network.sh"
# shellcheck source=lib/packages.sh
. "$BOOTSTRAP_LIB/packages.sh"
# shellcheck source=lib/users.sh
. "$BOOTSTRAP_LIB/users.sh"
# shellcheck source=lib/services.sh
. "$BOOTSTRAP_LIB/services.sh"
# shellcheck source=lib/templates.sh
. "$BOOTSTRAP_LIB/templates.sh"
# shellcheck source=lib/rollback.sh
. "$BOOTSTRAP_LIB/rollback.sh"
# shellcheck source=lib/config.sh
. "$BOOTSTRAP_LIB/config.sh"
# shellcheck source=lib/ensure.sh
. "$BOOTSTRAP_LIB/ensure.sh"
# shellcheck source=lib/doctor.sh
. "$BOOTSTRAP_LIB/doctor.sh"
# shellcheck source=lib/runner.sh
. "$BOOTSTRAP_LIB/runner.sh"

# Trap ERR for nicer error messages.
trap 'log_error "failed at line $LINENO: ${BASH_COMMAND:-?}"' ERR

usage() {
  cat <<EOF
BootstrapX v${BOOTSTRAP_VERSION}

Usage:
  bootstrap.sh [options]
  bootstrap.sh doctor [--json]
  bootstrap.sh resume
  bootstrap.sh rollback [MODULE]
  bootstrap.sh version
  bootstrap.sh help

Options:
  --safe                  Default safety mode (also default; explicit for clarity)
  --force                 Skip safety prompts; not required for SSH/root-login gates
  --dry-run               Plan and report without mutating
  --non-interactive, -y   Assume "yes" to prompts that have a default
  --verbose, -v           Increase log verbosity
  --debug                 Maximum verbosity (implies --verbose)
  --config FILE           Path to bootstrap.conf (default: ./bootstrap.conf)
  --only MODULE           Run only the named module (e.g. 20-users)
  --stage N               Run only modules whose stage() returns N

Subcommands:
  doctor                  Diagnose the system, optionally write JSON report
  resume                  Re-run with the same options (alias for default run)
  rollback [MODULE]       Roll back changes; with MODULE, only that module
  version                 Print version and exit
  help                    Show this message
EOF
}

parse_args() {
  while (( $# )); do
    case "$1" in
      --dry-run) BOOTSTRAP_DRY_RUN=1 ;;
      --force)   BOOTSTRAP_FORCE=1; BOOTSTRAP_SAFE=0 ;;
      --safe)    BOOTSTRAP_SAFE=1 ;;
      --non-interactive|-y) BOOTSTRAP_NON_INTERACTIVE=1 ;;
      --verbose|-v) BOOTSTRAP_VERBOSE=1 ;;
      --debug)   BOOTSTRAP_DEBUG=1; BOOTSTRAP_VERBOSE=1 ;;
      --config)  shift; BOOTSTRAP_CONFIG="$1" ;;
      --only)    shift; BOOTSTRAP_ONLY="$1" ;;
      --stage)   shift; BOOTSTRAP_STAGE="$1" ;;
      --json)    DOCTOR_JSON_OUTPUT=1 ;;
      doctor|resume|rollback|version|help|-h|--help)
        BOOTSTRAP_CMD="${1#--}"
        BOOTSTRAP_CMD="${BOOTSTRAP_CMD#-}"
        ;;
      -*) die "unknown flag: $1 (try --help)" ;;
      *)  die "unexpected positional arg: $1 (try --help)" ;;
    esac
    shift
  done
}

confirm_admin_reconnect() {
  if (( BOOTSTRAP_NON_INTERACTIVE )); then
    log_warn "non-interactive: skipping admin-reconnect confirmation"
    log_warn "if the admin user cannot log in, re-running will not enable stage 2"
    return 0
  fi
  printf '\n'
  printf '>>> Reconnect as the admin user in a NEW terminal before continuing:\n'
  printf '    ssh %s@%s\n' "${ADMIN_USER:-admin}" "$(hostname)"
  printf '    cd %s\n' "$BOOTSTRAP_ROOT"
  printf '    sudo ./bootstrap.sh --safe\n\n'
  printf 'Press Enter ONLY AFTER you have successfully logged in: '
  read -r _
}

main_run() {
  bootstrap_log_init
  log_step "BootstrapX v${BOOTSTRAP_VERSION}"
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "DRY RUN: no changes will be made"
  fi
  runner_run_all
}

main_doctor() {
  bootstrap_log_init
  doctor_run
}

main_rollback() {
  bootstrap_log_init
  runner_rollback_all "${1:-}"
}

main_resume() {
  # Resume is identical to run; the runner detects already-completed modules.
  main_run
}

# confirm_admin_reconnect — prompt the operator to reconnect as the admin user
# before stage 2 may proceed. Modules call this; tests stub it.
confirm_admin_reconnect() {
  if (( BOOTSTRAP_NON_INTERACTIVE )); then
    log_warn "non-interactive: skipping admin-reconnect confirmation"
    return 0
  fi
  printf '\n'
  printf '>>> Reconnect as the admin user in a NEW terminal before continuing:\n'
  printf '    ssh %s@%s\n' "${ADMIN_USER:-admin}" "$(hostname)"
  printf '    cd %s\n' "$BOOTSTRAP_ROOT"
  printf '    sudo ./bootstrap.sh --safe\n\n'
  printf 'Press Enter ONLY AFTER you have successfully logged in: '
  read -r _
}

main_version() {
  printf 'BootstrapX %s\n' "$BOOTSTRAP_VERSION"
  printf 'Bash %s\n' "$BASH_VERSION"
  printf 'Root: %s\n' "$BOOTSTRAP_ROOT"
}

main_help() {
  usage
}

main() {
  parse_args "$@"
  case "$BOOTSTRAP_CMD" in
    run)       main_run ;;
    doctor)    main_doctor ;;
    resume)    main_resume ;;
    rollback)  main_rollback "${BOOTSTRAP_ONLY:-}" ;;
    version)   main_version ;;
    help)      main_help ;;
    *) die "unknown command: $BOOTSTRAP_CMD" ;;
  esac
}

main "$@"