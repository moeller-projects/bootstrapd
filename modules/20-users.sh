#!/usr/bin/env bash
# modules/20-users.sh — Stage 1: create admin/deploy/agent users, SSH keys, sudoers.
# This is the safety-critical module. Root login MUST stay enabled until the
# operator reconnects and confirms. The runner reads state/20-users.state and
# refuses to enter stage 2 unless status=admin_validated.
set -Eeuo pipefail

mod_20_users_description() { echo "Create admin/deploy/agent users, SSH keys, sudo"; }
mod_20_users_stage()       { echo "1"; }
mod_20_users_dependencies(){ echo "10-base"; }

_sudoers_snippet_admin() {
  cat <<'EOF'
Defaults env_reset
Defaults timestamp_timeout=15
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF
  printf '\n%%%s ALL=(ALL:ALL) NOPASSWD:ALL\n' "${ADMIN_USER:-admin}"
}

_sudoers_snippet_user() {
  local user="$1"
  cat <<EOF
# bootstrapx: standard user snippet for $user
Defaults env_reset
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF
  printf '%s ALL=(ALL) ALL\n' "$user"
}

mod_20_users_check() {
  user_exists "${ADMIN_USER:-admin}" || return 1
  local f="$BOOTSTRAP_STATE/20-users.state"
  [[ -f "$f" ]] || return 1
  local status
  status="$(awk -F= '/^status=/{print $2}' "$f")"
  [[ "$status" == "admin_validated" ]]
}

mod_20_users_install() {
  local admin="${ADMIN_USER:-admin}"
  local deploy="${DEPLOY_USER:-deploy}"
  local agent="${AGENT_USER:-agent}"

  # Admin group first.
  ensure_group "$admin"
  ensure_group sudo

  # Admin user.
  ensure_user "$admin"
  ensure_user_in_group "$admin" sudo

  # Optional users.
  if [[ -n "${DEPLOY_USER:-}" ]] && [[ "$deploy" != "$admin" ]]; then
    ensure_user "$deploy"
  fi
  if [[ -n "${AGENT_USER:-}" ]] && [[ "$agent" != "$admin" ]]; then
    ensure_user "$agent"
  fi

  # SSH keys.
  local keyline
  if [[ -n "${SSH_PUBLIC_KEYS:-}" ]]; then
    local -a keys=()
    while IFS= read -r keyline; do
      [[ -z "$keyline" || "$keyline" =~ ^[[:space:]]*# ]] && continue
      keys+=("$keyline")
    done <<<"$SSH_PUBLIC_KEYS"
    if (( ${#keys[@]} > 0 )); then
      ssh_install_authorized_keys "$admin" "${keys[@]}"
      [[ "$deploy" != "$admin" ]] && ssh_install_authorized_keys "$deploy" "${keys[@]}"
      [[ "$agent"  != "$admin" ]] && ssh_install_authorized_keys "$agent"  "${keys[@]}"
    fi
  fi

  # Sudoers.
  local snippet
  snippet="$(_sudoers_snippet_admin)"
  sudoers_install_snippet "$admin" "$snippet"

  # Make /etc/sudoers 0440 just in case.
  ensure_permission /etc/sudoers 0440 root:root

  # Record initial state; runner will upgrade to admin_validated when an
  # admin login is observed.
  runner_record_state "20-users" "awaiting_admin_validation"

  confirm_admin_reconnect

  # After the operator's confirmation, validate by checking that the admin
  # user can sudo without a password and has at least one key.
  if ! ssh_user_keycount "$admin" >/dev/null || [[ "$(ssh_user_keycount "$admin")" == "0" ]]; then
    log_warn "no SSH keys installed for $admin — refusing to mark validated"
    log_warn "set SSH_PUBLIC_KEYS in bootstrap.conf and re-run"
    return 1
  fi
  if ! sudo -n -u "$admin" true 2>/dev/null; then
    log_warn "$admin cannot sudo non-interactively — refusing to mark validated"
    return 1
  fi
  runner_record_state "20-users" "admin_validated"
}

mod_20_users_validate() {
  local admin="${ADMIN_USER:-admin}"
  user_exists "$admin" || { log_error "admin user missing: $admin"; return 1; }
  [[ "$(ssh_user_keycount "$admin")" -gt 0 ]] || { log_error "no SSH keys for $admin"; return 1; }
  local home
  home="$(getent passwd "$admin" | cut -d: -f6)"
  local mode
  mode="$(stat -c '%a' "$home/.ssh")"
  [[ "$mode" == "700" ]] || { log_error "~/.ssh must be 0700 (is $mode)"; return 1; }
  mode="$(stat -c '%a' "$home/.ssh/authorized_keys")"
  [[ "$mode" == "600" ]] || { log_error "authorized_keys must be 0600 (is $mode)"; return 1; }
  sudo -n -u "$admin" true || { log_error "$admin sudo non-interactive failed"; return 1; }
}

mod_20_users_rollback() {
  local admin="${ADMIN_USER:-admin}"
  local deploy="${DEPLOY_USER:-deploy}"
  local agent="${AGENT_USER:-agent}"
  sudoers_remove_snippet "$admin"
  user_delete "$deploy"
  user_delete "$agent"
  # Don't delete the admin user — the operator may still be using it.
  rm -f -- "$BOOTSTRAP_STATE/20-users.state"
}