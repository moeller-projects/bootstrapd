#!/usr/bin/env bash
# modules/25-filesystem.sh — Stage 1: shared /srv hierarchy.
#
# /srv is the single source of truth for shared runtime data:
#   workspace/   human-readable working area, owned by admin
#   repos/       shared git checkouts (CI/CD mounts here)
#   cache/       package/build cache shared across users
#   artifacts/   build outputs, container images, model snapshots
#   logs/        service logs (besides /var/log)
#   backups/     framework + per-module backups (rsync-friendly)
#   models/      LLM weights, fine-tunes (agent-owned)
#
# Per-user dotfiles and personal repos stay under /home/<user>.
# This module only creates directories and sets baseline ownership.
set -Eeuo pipefail

mod_25_filesystem_description()
{
  echo "Create /srv hierarchy with role-based ownership"
}
mod_25_filesystem_stage()
{
  echo "1"
}
mod_25_filesystem_dependencies()
{
  echo "20-users"
}

_srv_root()
{
  printf '%s\n' "${SRV_ROOT:-/srv}"
}
_admin_user()
{
  printf '%s\n' "${ADMIN_USER:-admin}"
}
_deploy_user()
{
  printf '%s\n' "${DEPLOY_USER:-deploy}"
}
_agent_user()
{
  printf '%s\n' "${AGENT_USER:-agent}"
}

# Each entry: "<path> <mode> <owner>"
SRV_LAYOUT=(
  "$(_srv_root)                    0755 root:root"
  "$(_srv_root)/workspace          0775 $(_admin_user):$(_admin_user)"
  "$(_srv_root)/repos              0775 $(_admin_user):$(_deploy_user)"
  "$(_srv_root)/cache              0775 root:root"
  "$(_srv_root)/artifacts          0775 root:root"
  "$(_srv_root)/logs               0775 root:root"
  "$(_srv_root)/backups            0700 root:root"
  "$(_srv_root)/models             0750 $(_agent_user):$(_agent_user)"
  "$(_srv_root)/agent              0750 $(_agent_user):$(_agent_user)"
  "$(_srv_root)/agent/workspace    0750 $(_agent_user):$(_agent_user)"
  "$(_srv_root)/agent/cache        0750 $(_agent_user):$(_agent_user)"
  "$(_srv_root)/agent/logs         0750 $(_agent_user):$(_agent_user)"
  "$(_srv_root)/agent/models       0750 $(_agent_user):$(_agent_user)"
)

mod_25_filesystem_check()
{
  [[ -d "$(_srv_root)" ]] || return 1
  [[ -d "$(_srv_root)/workspace" ]] || return 1
  [[ -d "$(_srv_root)/agent" ]] || return 1
  return 0
}

mod_25_filesystem_install()
{
  local entry path mode owner
  for entry in "${SRV_LAYOUT[@]}"; do
    # Use a here-string split; avoid eval, no expansion of user-controlled data.
    path="${entry%% *}"
    local rest="${entry#* }"
    mode="${rest%% *}"
    owner="${rest#* }"
    ensure_directory "$path" "$mode" "$owner"
  done

  # Make the agent's runtime dirs match its workspace.
  local agent
  agent="$(_agent_user)"
  if user_exists "$agent"; then
    # Symlink the per-user agent home references into /srv/agent for tooling that
    # expects $HOME/workspace, $HOME/cache, $HOME/logs, $HOME/models.
    local home
    home="$(getent passwd "$agent" | cut -d: -f6)"
    for sub in workspace cache logs models; do
      if [[ "$home/$sub" != "/srv/agent/$sub" ]]; then
        ensure_symlink "$home/$sub" "/srv/agent/$sub"
      fi
    done
  fi

  # Backups: per-module backups already live under BOOTSTRAP_STATE/backups.
  # Mirror a top-level /srv/backups for host-level rsync/snapshot tooling.
  log_info "filesystem layout ready under $(_srv_root)"
}

mod_25_filesystem_validate()
{
  local entry path mode owner
  for entry in "${SRV_LAYOUT[@]}"; do
    path="${entry%% *}"
    [[ -d "$path" ]] || {
      log_error "missing: $path"
      return 1
    }
  done
  return 0
}

mod_25_filesystem_rollback()
{
  # Don't rm -rf /srv — too dangerous. Leave the directories in place; the
  # next run will re-apply permissions if they drifted.
  :
}
