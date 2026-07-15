#!/usr/bin/env bash
# modules/28-tailscale.sh — Stage 2: Tailscale mesh VPN.
set -Eeuo pipefail

mod_28_tailscale_description()
{
  echo "Tailscale mesh VPN"
}
mod_28_tailscale_stage()
{
  echo "2"
}
mod_28_tailscale_dependencies()
{
  echo "20-users"
}

_install_tailscale()
{
  local tmp
  tmp="$(mktemp -d)"
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would install Tailscale via tailscale.com/install.sh"
    rm -rf "$tmp"
    return 0
  fi

  curl --fail --location --silent --show-error --connect-timeout 15 --max-time 600 \
    -o "$tmp/install.sh" -- "https://tailscale.com/install.sh" || {
    rm -rf "$tmp"
    return 1
  }
  sh "$tmp/install.sh" || {
    rm -rf "$tmp"
    return 1
  }
  rm -rf "$tmp"
}

mod_28_tailscale_check()
{
  bootstrap_config_bool ENABLE_TAILSCALE || return 0
  command -v tailscale >/dev/null 2>&1 || return 1
  svc_active tailscaled || return 1
  tailscale status >/dev/null 2>&1 || return 1
}

mod_28_tailscale_install()
{
  bootstrap_config_bool ENABLE_TAILSCALE || return 0

  if ! command -v tailscale >/dev/null 2>&1; then
    log_info "installing Tailscale"
    _install_tailscale || return 1
  fi

  ensure_service_enabled tailscaled
  ensure_service_running tailscaled

  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would enroll Tailscale"
    return 0
  fi

  local hostname="${HOSTNAME:-$(hostname)}"
  if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
    log_info "enrolling Tailscale with auth key"
    tailscale up --hostname="$hostname" --authkey="$TAILSCALE_AUTH_KEY"
    return $?
  fi

  if [[ "${BOOTSTRAP_NON_INTERACTIVE:-0}" == "1" ]]; then
    log_error "TAILSCALE_AUTH_KEY is required for non-interactive Tailscale enrollment"
    return 1
  fi

  log_info "enrolling Tailscale interactively"
  tailscale up --hostname="$hostname"
}

mod_28_tailscale_validate()
{
  bootstrap_config_bool ENABLE_TAILSCALE || return 0
  command -v tailscale >/dev/null 2>&1 || {
    log_error "tailscale missing"
    return 1
  }
  svc_active tailscaled || {
    log_error "tailscaled not active"
    return 1
  }
  tailscale status >/dev/null 2>&1 || {
    log_error "tailscale not connected"
    return 1
  }
  return 0
}

mod_28_tailscale_rollback()
{
  if command -v tailscale >/dev/null 2>&1; then
    tailscale down >/dev/null 2>&1 || true
  fi
  ensure_service_disabled tailscaled 2>/dev/null || true
}
