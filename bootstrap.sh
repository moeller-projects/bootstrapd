#!/usr/bin/env bash
# BootstrapX — main entry point.
# See README.md, ARCHITECTURE.md.
set -Eeuo pipefail

BOOTSTRAP_VERSION="0.2.0"
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

# Modes / flags (set by CLI parsing). Marked export so shellcheck treats them
# as consumed; the parse_args function sets them and other functions read them.
export BOOTSTRAP_CMD="apply"
export BOOTSTRAP_DRY_RUN=0
export BOOTSTRAP_FORCE=0
export BOOTSTRAP_SAFE=1
export BOOTSTRAP_VERBOSE=0
export BOOTSTRAP_DEBUG=0
export BOOTSTRAP_NON_INTERACTIVE=0
export BOOTSTRAP_ONLY=""
export BOOTSTRAP_STAGE=""
export BOOTSTRAP_CMD_ARGS=()
export DOCTOR_JSON_OUTPUT=0

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

trap 'log_error "failed at line $LINENO: ${BASH_COMMAND:-?}"' ERR

usage()
{
  cat <<EOF
BootstrapX v${BOOTSTRAP_VERSION}

Usage:
  bootstrap.sh <command> [options]

Commands:
  apply                  Reconcile the system to the desired state in bootstrap.conf
  validate               Verify modules and config without applying
  status                 Show the recorded state of every module
  doctor                 Run the full diagnostic suite (Markdown + JSON)
  update                 Pull the latest framework and re-apply
  backup [DIR]           Snapshot the state directory to DIR (default ./backups)
  restore SNAPSHOT       Restore state from a snapshot tarball
  rollback [MODULE]      Roll back changes; with MODULE, only that module
  clean                  Remove transient state (logs, plan files); keep backups
  version                Print version and exit
  help                   Show this message

Options (apply/validate/status/update):
  --safe                 Default safety mode (also default)
  --force                Skip safety prompts
  --dry-run              Plan and report without mutating
  --non-interactive, -y  Assume "yes" to prompts
  --verbose, -v          Increase log verbosity
  --debug                Maximum verbosity (implies --verbose)
  --config FILE          Path to bootstrap.conf (default: ./bootstrap.conf)
  --only MODULE          Run only the named module (e.g. 20-users)
  --stage N              Run only modules whose stage() returns N

Examples:
  sudo ./bootstrap.sh apply
  sudo ./bootstrap.sh apply --only 30-security
  sudo ./bootstrap.sh status
  sudo ./bootstrap.sh doctor --json
  sudo ./bootstrap.sh backup /var/backups
  sudo ./bootstrap.sh restore /var/backups/bootstrapx-20260710.tgz
EOF
}

parse_args()
{
  BOOTSTRAP_CMD="apply"
  while (($#)); do
    case "$1" in
      --dry-run) BOOTSTRAP_DRY_RUN=1 ;;
      --force)
        BOOTSTRAP_FORCE=1
        BOOTSTRAP_SAFE=0
        ;;
      --safe) BOOTSTRAP_SAFE=1 ;;
      --non-interactive | -y) BOOTSTRAP_NON_INTERACTIVE=1 ;;
      --verbose | -v) BOOTSTRAP_VERBOSE=1 ;;
      --debug)
        BOOTSTRAP_DEBUG=1
        BOOTSTRAP_VERBOSE=1
        ;;
      --config)
        shift
        BOOTSTRAP_CONFIG="$1"
        ;;
      --only)
        shift
        BOOTSTRAP_ONLY="$1"
        ;;
      --stage)
        shift
        BOOTSTRAP_STAGE="$1"
        ;;
      --json) DOCTOR_JSON_OUTPUT=1 ;;
      apply | validate | status | doctor | update | backup | restore | rollback | clean | version | help | -h | --help)
        BOOTSTRAP_CMD="${1#--}"
        BOOTSTRAP_CMD="${BOOTSTRAP_CMD#-}"
        ;;
      -*) die "unknown flag: $1 (try --help)" ;;
      *) BOOTSTRAP_CMD_ARGS+=("$1") ;;
    esac
    shift
  done
}

# --- commands ---

main_apply()
{
  bootstrap_log_init
  log_step "BootstrapX v${BOOTSTRAP_VERSION} — apply"
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "DRY RUN: no changes will be made"
  fi
  runner_run_all
}

main_validate()
{
  bootstrap_log_init
  bootstrap_config_load
  log_step "BootstrapX v${BOOTSTRAP_VERSION} — validate"
  local ids id fn rc=0
  ids="$(runner_discover_modules)"
  runner_load_modules
  if ! runner_validate_module_api; then
    rc=1
  fi
  log_step "per-module check()"
  while read -r id; do
    [[ -z "$id" ]] && continue
    fn="$(_module_function_name "$id" check)"
    if declare -F -- "$fn" >/dev/null; then
      if "$fn"; then
        printf 'OK    %s\n' "$id"
      else
        printf 'NEED  %s\n' "$id"
        rc=1
      fi
    fi
  done <<<"$ids"
  return "$rc"
}

main_status()
{
  bootstrap_log_init
  bootstrap_config_load
  log_step "BootstrapX v${BOOTSTRAP_VERSION} — status"
  local ids f status installed_at
  ids="$(runner_discover_modules)"
  printf '%-22s %-22s %-25s\n' "MODULE" "STATUS" "INSTALLED_AT"
  printf -- '------------------------------------------------------------\n'
  while read -r id; do
    [[ -z "$id" ]] && continue
    f="$BOOTSTRAP_STATE/${id}.state"
    if [[ -f "$f" ]]; then
      status="$(awk -F= '/^status=/{print $2}' "$f")"
      installed_at="$(awk -F= '/^installed_at=/{print $2}' "$f")"
      printf '%-22s %-22s %-25s\n' "$id" "$status" "$installed_at"
    else
      printf '%-22s %-22s %-25s\n' "$id" "never_run" "-"
    fi
  done <<<"$ids"
}

main_doctor()
{
  bootstrap_log_init
  doctor_run
}

main_update()
{
  bootstrap_log_init
  log_step "BootstrapX v${BOOTSTRAP_VERSION} — update"
  if [[ -d "$BOOTSTRAP_ROOT/.git" ]]; then
    log_info "git pull in $BOOTSTRAP_ROOT"
    if ((!BOOTSTRAP_DRY_RUN)); then
      (cd "$BOOTSTRAP_ROOT" && git pull --ff-only) ||
        log_warn "git pull failed; continuing with current sources"
    fi
  else
    log_warn "no .git in $BOOTSTRAP_ROOT; skipping pull"
  fi
  main_apply
}

main_backup()
{
  bootstrap_log_init
  local dest="${BOOTSTRAP_CMD_ARGS[0]:-$BOOTSTRAP_ROOT/backups}"
  mkdir -p "$dest"
  local stamp out
  stamp="$(date -u +'%Y%m%dT%H%M%SZ')"
  out="$dest/bootstrapx-${stamp}.tgz"
  log_step "snapshotting state -> $out"
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would write $out"
    return 0
  fi
  (cd "$BOOTSTRAP_ROOT" && tar --exclude='./backups' --exclude='./state/backups' \
    -czf "$out" state bootstrap.conf 2>/dev/null) ||
    (cd "$BOOTSTRAP_ROOT" && tar -czf "$out" state 2>/dev/null)
  log_success "wrote $out"
}

main_restore()
{
  bootstrap_log_init
  local snapshot="${BOOTSTRAP_CMD_ARGS[0]:-}"
  [[ -n "$snapshot" ]] || die "usage: bootstrap restore <snapshot.tgz>"
  [[ -f "$snapshot" ]] || die "snapshot not found: $snapshot"
  log_step "restoring state from $snapshot"
  if ((!BOOTSTRAP_DRY_RUN)); then
    tar -xzf "$snapshot" -C "$BOOTSTRAP_ROOT"
    log_success "restored"
  fi
}

main_rollback()
{
  bootstrap_log_init
  runner_rollback_all "${BOOTSTRAP_CMD_ARGS[0]:-}"
}

main_clean()
{
  bootstrap_log_init
  log_step "BootstrapX v${BOOTSTRAP_VERSION} — clean"
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would remove *.log and *.tmp under state/"
    return 0
  fi
  find "$BOOTSTRAP_STATE" -maxdepth 1 -type f \
    \( -name '*.log' -o -name '*.tmp' \) -delete 2>/dev/null || true
  log_success "cleaned"
}

confirm_admin_reconnect()
{
  if ((BOOTSTRAP_NON_INTERACTIVE)); then
    log_warn "non-interactive: skipping admin-reconnect confirmation"
    return 0
  fi
  printf '\n'
  printf '>>> Reconnect as the admin user in a NEW terminal before continuing:\n'
  printf '    ssh %s@%s\n' "${ADMIN_USER:-admin}" "$(hostname)"
  printf '    cd %s\n' "$BOOTSTRAP_ROOT"
  printf '    sudo ./bootstrap.sh apply --safe\n\n'
  printf 'Press Enter ONLY AFTER you have successfully logged in: '
  read -r _
}

main_version()
{
  printf 'BootstrapX %s\n' "$BOOTSTRAP_VERSION"
  printf 'Bash %s\n' "$BASH_VERSION"
  printf 'Root: %s\n' "$BOOTSTRAP_ROOT"
}

main_help()
{
  usage
}

main()
{
  BOOTSTRAP_CMD_ARGS=()
  parse_args "$@"
  case "$BOOTSTRAP_CMD" in
    apply) main_apply ;;
    validate) main_validate ;;
    status) main_status ;;
    doctor) main_doctor ;;
    update) main_update ;;
    backup) main_backup ;;
    restore) main_restore ;;
    rollback) main_rollback ;;
    clean) main_clean ;;
    version) main_version ;;
    help) main_help ;;
    *) die "unknown command: $BOOTSTRAP_CMD (try --help)" ;;
  esac
}

main "$@"
