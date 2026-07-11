#!/usr/bin/env bash
# lib/runner.sh — module discovery, dependency-graph resolution, staged execution.
# Deps: log, fs, system, config, ensure (transitively).
set -Eeuo pipefail

# _module_id_from_filename FILE  → "10-base"
_module_id_from_filename()
{
  local f="$1" bn
  bn="$(basename -- "$f")"
  bn="${bn%.sh}"
  printf '%s\n' "$bn"
}

# _module_function_name ID SUFFIX  → "mod_10_base_description"
# Replaces dashes with underscores for valid bash identifiers.
_module_function_name()
{
  local id="$1" suffix="$2"
  local safe="${id//-/_}"
  printf 'mod_%s_%s\n' "$safe" "$suffix"
}

# _module_required_functions  → echoes the list of required function suffixes.
_module_required_functions()
{
  printf '%s\n' description stage dependencies check install validate rollback
}

# Discover modules in $BOOTSTRAP_MODULES, sorted by NN prefix.
# Echoes module IDs, one per line.
runner_discover_modules()
{
  local f id
  for f in "$BOOTSTRAP_MODULES"/*.sh; do
    [[ -e "$f" ]] || continue
    id="$(_module_id_from_filename "$f")"
    if [[ ! "$id" =~ ^[0-9]{2}- ]]; then
      log_warn "skipping module without NN- prefix: $f"
      continue
    fi
    printf '%s\n' "$id"
  done | sort
}

# Load (source) every module file directly from the modules directory.
# Idempotent: skips files without a NN- prefix and dedupes by ID.
runner_load_modules()
{
  local -A seen=()
  local f id
  for f in "$BOOTSTRAP_MODULES"/*.sh; do
    [[ -e "$f" ]] || continue
    id="$(_module_id_from_filename "$f")"
    if [[ ! "$id" =~ ^[0-9]{2}- ]]; then
      log_warn "skipping module without NN- prefix: $f"
      continue
    fi
    [[ -n "${seen[$id]:-}" ]] && {
      log_warn "duplicate module id: $id"
      continue
    }
    seen[$id]=1
    # shellcheck disable=SC1090
    . "$f"
    log_debug "loaded module: $id"
  done
}

# Validate that all required functions are defined for every module.
runner_validate_module_api()
{
  local -A seen=()
  local f id fn suf missing=0
  for f in "$BOOTSTRAP_MODULES"/*.sh; do
    [[ -e "$f" ]] || continue
    id="$(_module_id_from_filename "$f")"
    [[ ! "$id" =~ ^[0-9]{2}- ]] && continue
    [[ -n "${seen[$id]:-}" ]] && continue
    seen[$id]=1
    while read -r suf; do
      fn="$(_module_function_name "$id" "$suf")"
      if ! declare -F -- "$fn" >/dev/null; then
        log_error "module $id: missing function $fn"
        missing=1
      fi
    done < <(_module_required_functions)
  done
  return "$missing"
}

# Topological sort lives entirely in Bash below (runner_toposort_bash).
# The pure-Bash version handles our small graph (typically <30 modules) without
# needing a Python interpreter on the target.

# _module_dependencies ID  → space-separated dep IDs (resolved by sourcing the module's
# mod_NN_dependencies() function — but the runner sources all modules first, so this is just
# a function call).
_module_dependencies()
{
  local id="$1"
  local fn
  fn="$(_module_function_name "$id" "dependencies")"
  "$fn"
}

# Topological sort using a pure-Bash implementation (fallback if python3 is absent).
runner_toposort_bash()
{
  local id
  local ids=()
  while read -r id; do
    ids+=("$id")
  done
  [[ ${#ids[@]} -eq 0 ]] && return 0
  declare -A DEP
  for id in "${ids[@]}"; do
    DEP[$id]="$(_module_dependencies "$id")"
  done
  local placed=0 placed_max=${#ids[@]}
  declare -A PLACED
  local pass=0
  while ((placed < placed_max)); do
    ((pass++)) || true
    if ((pass > placed_max + 5)); then
      log_error "dependency cycle detected"
      return 1
    fi
    for id in "${ids[@]}"; do
      [[ -n "${PLACED[$id]:-}" ]] && continue
      local ready=1 d
      for d in ${DEP[$id]}; do
        if [[ -z "${PLACED[$d]:-}" ]] && [[ " ${ids[*]} " == *" $d "* ]]; then
          ready=0
          break
        fi
      done
      if ((ready)); then
        printf '%s\n' "$id"
        PLACED[$id]=1
        placed=$((placed + 1))
      fi
    done
  done
}

# Run a single module end to end.
runner_run_module()
{
  local id="$1"
  local fn desc stage
  fn="$(_module_function_name "$id" "description")"
  desc="$($fn)"
  fn="$(_module_function_name "$id" "stage")"
  stage="$($fn)"

  local req_stage="${BOOTSTRAP_STAGE:-}"
  local req_only="${BOOTSTRAP_ONLY:-}"

  if [[ -n "$req_stage" && "$stage" != "$req_stage" ]]; then
    log_debug "skipping $id (stage $stage != requested $req_stage)"
    return 0
  fi
  if [[ -n "$req_only" && "$id" != "$req_only" ]]; then
    log_debug "skipping $id (not in --only)"
    return 0
  fi

  log_step "module $id (stage $stage): $desc"

  if [[ "$BOOTSTRAP_SAFE" == "1" && "$stage" == "2" ]]; then
    if ! runner_safety_prerequisite; then
      log_error "stage 2 safety prerequisite not met; refusing to continue"
      log_error "reconnect as $ADMIN_USER from a second terminal and re-run ./bootstrap.sh --safe"
      return 1
    fi
  fi

  fn="$(_module_function_name "$id" "check")"
  local check_rc=0
  if ((BOOTSTRAP_FORCE)); then
    check_rc=1
    log_debug "force mode: ignoring check()"
  else
    "$fn" || check_rc=$?
  fi

  if ((check_rc == 0)); then
    log_debug "$id already satisfied; skipping install"
  else
    fn="$(_module_function_name "$id" "install")"
    if ! "$fn"; then
      log_error "$id install failed"
      local rb_fn
      rb_fn="$(_module_function_name "$id" "rollback")"
      "$rb_fn" 2>/dev/null || true
      return 1
    fi
    fn="$(_module_function_name "$id" "validate")"
    if ! "$fn"; then
      log_error "$id validate failed"
      local rb_fn2
      rb_fn2="$(_module_function_name "$id" "rollback")"
      "$rb_fn2" 2>/dev/null || true
      return 1
    fi
  fi
  # Only auto-record if the module didn't record its own status (e.g. 20-users
  # records 'awaiting_admin_validation' then 'admin_validated' to gate stage 2).
  if [[ ! -f "$BOOTSTRAP_STATE/${id}.state" ]]; then
    runner_record_state "$id" "ok"
  fi
  log_success "$id done"
}

runner_record_state()
{
  local id="$1" status="$2"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  local path="$BOOTSTRAP_STATE/${id}.state"
  local ts
  ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  local checksum=""
  if [[ -d "$BOOTSTRAP_MODULES" ]]; then
    checksum="$(sha256sum "$BOOTSTRAP_MODULES/${id}.sh" | awk '{print $1}')"
  fi
  cat >"$path" <<EOF
status=${status}
installed_at=${ts}
module_checksum=${checksum}
EOF
}

runner_safety_prerequisite()
{
  # Required state file from the users module, with status=awaiting_admin_validation cleared
  # by a second-terminal reconnect.
  local f="$BOOTSTRAP_STATE/20-users.state"
  [[ -f "$f" ]] || return 1
  local status
  status="$(awk -F= '/^status=/{print $2}' "$f")"
  [[ "$status" == "admin_validated" ]]
}

runner_preflight()
{
  bootstrap_system_supported || return 1
  bootstrap_system_require_root || return 1
  log_info "distro=$(bootstrap_system_distro) version=$(bootstrap_system_version) arch=$(bootstrap_system_arch)"
  net_wait_online 30 || {
    log_error "no internet after 30s"
    return 1
  }
  net_dns_resolves deb.debian.org || net_dns_resolves archive.ubuntu.com ||
    {
      log_error "DNS resolution failed"
      return 1
    }
  local disk
  disk="$(df --output=avail -BG / | awk 'NR==2 {gsub("G",""); print $1}')"
  ((disk >= 5)) || {
    log_error "less than 5 GiB free on /"
    return 1
  }
  local mem
  mem="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
  ((mem >= 1024)) || {
    log_error "less than 1 GiB RAM"
    return 1
  }
  log_success "preflight ok (free disk >=${disk}G, RAM ${mem}MiB)"
}

runner_run_all()
{
  bootstrap_log_init
  bootstrap_config_load
  bootstrap_config_summary
  runner_preflight || return 1
  log_step "discovering modules"
  local ids
  ids="$(runner_discover_modules)"
  if [[ -z "$ids" ]]; then
    log_warn "no modules found in $BOOTSTRAP_MODULES"
    return 0
  fi
  log_debug "modules discovered:"
  while read -r id; do log_debug "  $id"; done <<<"$ids"

  runner_load_modules || return 1
  runner_validate_module_api || return 1
  echo "test" >/dev/null

  # Sort
  local ordered
  ordered="$(printf '%s\n' "$ids" | runner_toposort_bash)"
  [[ -z "$ordered" ]] && {
    log_error "toposort failed"
    return 1
  }

  log_step "execution plan:"
  while read -r id; do
    log_info "  - $id"
  done <<<"$ordered"

  local rc=0
  while read -r id; do
    if ! runner_run_module "$id"; then
      rc=1
      log_error "aborting due to failure in $id"
      break
    fi
  done <<<"$ordered"

  if ((rc == 0)); then
    log_done "bootstrap complete"
  fi
  return "$rc"
}

runner_rollback_all()
{
  local target="${1:-}"
  bootstrap_log_init
  if [[ -n "$target" ]]; then
    log_step "rolling back module: $target"
  else
    log_step "rolling back everything"
  fi
  bootstrap_config_load
  local id fn
  for f in "$BOOTSTRAP_MODULES"/*.sh; do
    [[ -e "$f" ]] || continue
    id="$(_module_id_from_filename "$f")"
    if [[ -n "$target" && "$id" != "$target" ]]; then
      continue
    fi
    # shellcheck disable=SC1090
    . "$f"
    fn="$(_module_function_name "$id" "rollback")"
    if declare -F -- "$fn" >/dev/null; then
      log_info "  $id"
      "$fn" || log_warn "rollback step failed: $id"
    fi
  done
  replay_rollback "$target"
  log_done "rollback complete"
}
