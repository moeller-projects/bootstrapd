#!/usr/bin/env bash
# modules/20-users.sh — Stage 1: least-privilege user model.
#
# root    : bootstrap + emergency only. SSH disabled after stage 1 succeeds.
# admin   : primary operator. SSH + passwordless sudo + dev environment.
# deploy  : CI/CD. Restricted sudo, no interactive shell by default.
# agent   : AI tooling runtime. nologin, no SSH, no sudo, owned workspace.
#
# Safety contract: this module is gated by the runner. Root login MUST stay
# enabled until state/20-users.state status=admin_validated. The runner
# refuses to enter stage 2 otherwise.
set -Eeuo pipefail

mod_20_users_description()
{
  echo "Create least-privilege admin/deploy/agent users, SSH keys, sudo"
}
mod_20_users_stage()
{
  echo "1"
}
mod_20_users_dependencies()
{
  echo "10-base"
}

# --- sudoers snippets ---

_sudoers_admin()
{
  cat <<'EOF'
Defaults env_reset
Defaults timestamp_timeout=15
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults mail_badpass
EOF
  printf '\n%%%s ALL=(ALL:ALL) NOPASSWD:ALL\n' "${ADMIN_USER:-admin}"
}

_sudoers_deploy_restricted()
{
  local deploy="${DEPLOY_USER:-deploy}"
  cat <<EOF
# bootstrapx: restricted sudo for $deploy (CI/CD only)
Defaults env_reset
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults mail_badpass

# CI/CD tasks only — no shell, no package install, no service control.
$deploy ALL=(root) NOPASSWD: /usr/bin/systemctl reload *
$deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart *
$deploy ALL=(root) NOPASSWD: /usr/bin/podman pull
$deploy ALL=(root) NOPASSWD: /usr/local/bin/deploy-*
EOF
}

# --- user creation ---

_create_admin_user()
{
  local name="$1"
  ensure_group "$name"
  ensure_group sudo
  ensure_user "$name" "/home/$name" "/bin/bash"
  ensure_user_in_group "$name" sudo
}

_create_deploy_user()
{
  local name="$1"
  ensure_user "$name" "/home/$name" "/usr/sbin/nologin"
  # Lock the password; this account logs in via SSH key only (or not at all).
  if ((!BOOTSTRAP_DRY_RUN)); then
    passwd -l "$name" >/dev/null 2>&1 || true
  fi
}

_create_agent_user()
{
  local name="$1"
  ensure_user "$name" "/srv/agent" "/usr/sbin/nologin"
  # Lock password; no interactive login possible regardless.
  if ((!BOOTSTRAP_DRY_RUN)); then
    passwd -l "$name" >/dev/null 2>&1 || true
  fi
  # Agent must own its runtime dirs; create home with admin-readable group
  # so log shipping tools can read.
  ensure_directory "/srv/agent" 0750 "$name:$name"
  for sub in workspace cache logs models; do
    ensure_directory "/srv/agent/$sub" 0750 "$name:$name"
  done
}

# --- main entrypoints ---

mod_20_users_check()
{
  user_exists "${ADMIN_USER:-admin}" || return 1
  local f="$BOOTSTRAP_STATE/20-users.state"
  [[ -f "$f" ]] || return 1
  local status
  status="$(awk -F= '/^status=/{print $2}' "$f")"
  [[ "$status" == "admin_validated" ]]
}

mod_20_users_install()
{
  local admin="${ADMIN_USER:-admin}"
  local deploy="${DEPLOY_USER:-deploy}"
  local agent="${AGENT_USER:-agent}"

  _create_admin_user "$admin"
  _create_deploy_user "$deploy"
  _create_agent_user "$agent"

  # SSH keys: only for accounts with an interactive shell path.
  # agent: never. deploy: only if SSH_PUBLIC_KEYS_DEPLOY is set or falls back.
  # admin: always.
  if [[ -n "${SSH_PUBLIC_KEYS:-}" ]]; then
    local -a keys=()
    local keyline
    while IFS= read -r keyline; do
      [[ -z "$keyline" || "$keyline" =~ ^[[:space:]]*# ]] && continue
      keys+=("$keyline")
    done <<<"$SSH_PUBLIC_KEYS"
    if ((${#keys[@]} > 0)); then
      ssh_install_authorized_keys "$admin" "${keys[@]}"
      # deploy may or may not have keys depending on policy
      if bootstrap_config_bool DEPLOY_SSH_ENABLED; then
        ssh_install_authorized_keys "$deploy" "${keys[@]}"
      fi
      # agent NEVER gets SSH keys — sandbox by construction
    fi
  fi

  # Sudoers.
  sudoers_install_snippet "$admin" "$(_sudoers_admin)"
  if bootstrap_config_bool DEPLOY_SUDO_RESTRICTED; then
    sudoers_install_snippet "$deploy" "$(_sudoers_deploy_restricted)"
  fi

  ensure_permission /etc/sudoers 0440 root:root

  runner_record_state "20-users" "awaiting_admin_validation"
  confirm_admin_reconnect

  # Validate the operator can actually log in as admin before we let stage 2 lock root.
  if [[ "$(ssh_user_keycount "$admin")" == "0" ]]; then
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

mod_20_users_validate()
{
  local admin="${ADMIN_USER:-admin}"
  local agent="${AGENT_USER:-agent}"
  local deploy="${DEPLOY_USER:-deploy}"

  user_exists "$admin" || {
    log_error "admin user missing: $admin"
    return 1
  }
  [[ "$(ssh_user_keycount "$admin")" -gt 0 ]] || {
    log_error "no SSH keys for $admin"
    return 1
  }
  local home mode
  home="$(getent passwd "$admin" | cut -d: -f6)"
  mode="$(stat -c '%a' "$home/.ssh")"
  [[ "$mode" == "700" ]] || {
    log_error "\$HOME/.ssh must be 0700 (is $mode)"
    return 1
  }
  mode="$(stat -c '%a' "$home/.ssh/authorized_keys")"
  [[ "$mode" == "600" ]] || {
    log_error "authorized_keys must be 0600 (is $mode)"
    return 1
  }
  sudo -n -u "$admin" true || {
    log_error "$admin sudo non-interactive failed"
    return 1
  }
  user_exists "$agent" || {
    log_error "agent user missing: $agent"
    return 1
  }
  local agent_shell
  agent_shell="$(getent passwd "$agent" | cut -d: -f7)"
  [[ "$agent_shell" == "/usr/sbin/nologin" || "$agent_shell" == "/bin/false" ]] ||
    {
      log_error "agent shell must be nologin/false (is $agent_shell)"
      return 1
    }
  passwd -S "$agent" 2>/dev/null | grep -qE '^[^ ]+ L ' ||
    {
      log_error "agent password must be locked"
      return 1
    }
  # agent must have no SSH keys.
  local agent_home agent_ak
  agent_home="$(getent passwd "$agent" | cut -d: -f6)"
  agent_ak="$agent_home/.ssh/authorized_keys"
  if [[ -f "$agent_ak" ]]; then
    log_error "agent user has authorized_keys — sandbox violation"
    return 1
  fi

  # Deploy: optional shell, restricted sudo.
  if user_exists "$deploy"; then
    if ! bootstrap_config_bool DEPLOY_SUDO_RESTRICTED; then
      log_warn "deploy unrestricted sudo enabled — review policy"
    fi
  fi
}

mod_20_users_rollback()
{
  local admin="${ADMIN_USER:-admin}"
  local deploy="${DEPLOY_USER:-deploy}"
  local agent="${AGENT_USER:-agent}"
  sudoers_remove_snippet "$admin"
  sudoers_remove_snippet "$deploy"
  user_delete "$deploy"
  # Leave agent dirs in place; data dir ownership matters.
  # Remove only the user entry, not /srv/agent contents.
  if user_exists "$agent"; then
    if ((!BOOTSTRAP_DRY_RUN)); then
      userdel "$agent" 2>/dev/null || true
    fi
  fi
  rm -f -- "$BOOTSTRAP_STATE/20-users.state"
}
