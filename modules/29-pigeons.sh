#!/usr/bin/env bash
# modules/29-pigeons.sh — Stage 2: optional SSH-over-QUIC access via Pigeons.
set -Eeuo pipefail

mod_29_pigeons_description()
{
  echo "Optional Pigeons SSH tunnel service"
}
mod_29_pigeons_stage()
{
  echo "2"
}
mod_29_pigeons_dependencies()
{
  echo "20-users"
}

_install_pigeons()
{
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would run curl -fSsL https://vorc.s3.us-east-2.amazonaws.com/pigeons-install.sh | bash"
    return 0
  fi

  curl -fSsL https://vorc.s3.us-east-2.amazonaws.com/pigeons-install.sh | bash || {
    return 1
  }
}

mod_29_pigeons_check()
{
  bootstrap_config_bool ENABLE_PIGEONS || return 0
  command -v pigeons >/dev/null 2>&1 || return 1
  systemctl is-active --quiet pigeons.service
}

mod_29_pigeons_install()
{
  bootstrap_config_bool ENABLE_PIGEONS || return 0

  if ! command -v pigeons >/dev/null 2>&1; then
    log_info "installing Pigeons"
    _install_pigeons || return 1
  fi

  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would install and enable pigeons.service"
    return 0
  fi

  pigeons service install --ssh-port "${SSH_PORT:-22}"
}

mod_29_pigeons_validate()
{
  bootstrap_config_bool ENABLE_PIGEONS || return 0
  command -v pigeons >/dev/null 2>&1 || {
    log_error "pigeons missing"
    return 1
  }
  systemctl is-active --quiet pigeons.service || {
    log_error "pigeons.service not active"
    return 1
  }
  return 0
}

mod_29_pigeons_rollback()
{
  if command -v pigeons >/dev/null 2>&1; then
    pigeons service uninstall >/dev/null 2>&1 || true
  fi
}
