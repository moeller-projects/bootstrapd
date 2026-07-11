#!/usr/bin/env bash
# lib/config.sh — load and validate bootstrap.conf.
# Deps: log, system.
set -Eeuo pipefail

# Default values for known keys. Anything not in this map falls back to "".
_BOOTSTRAP_DEFAULTS=(
  "HOSTNAME="
  "TIMEZONE=UTC"
  "LOCALE=en_US.UTF-8"
  "ADMIN_USER=admin"
  "DEPLOY_USER=deploy"
  "AGENT_USER=agent"
  "SSH_PORT=22"
  "ENABLE_PODMAN=true"
  "ENABLE_DOCKER=false"
  "ENABLE_OPENCLAW=true"
  "ENABLE_PI=true"
  "ENABLE_CODEX=true"
  "ENABLE_CLAUDE=true"
  "ENABLE_OLLAMA=false"
  "ENABLE_GITHUB_CLI=true"
  "ENABLE_TAILSCALE=false"
  "ENABLE_CADDY=false"
  "ENABLE_FAIL2BAN=true"
  "ENABLE_APPARMOR=true"
  "ENABLE_AUTO_UPDATES=true"
  "ENABLE_MONITORING=true"
  "NODE_VERSION=22"
  "DOTNET_CHANNEL=9.0"
  "PYTHON_VERSION=3.12"
  "PODMAN_STORAGE=/var/lib/containers/storage"
  "PODMAN_REGISTRIES=docker.io quay.io ghcr.io"
  "SSH_PUBLIC_KEYS="
)

bootstrap_config_load() {
  local path="${BOOTSTRAP_CONFIG:-$BOOTSTRAP_ROOT/bootstrap.conf}"
  if [[ ! -r "$path" ]]; then
    log_warn "config file not readable: $path (using defaults)"
  else
    # shellcheck disable=SC1090
    . "$path"
    log_debug "loaded config: $path"
  fi

  # Apply defaults for any unset key.
  local entry key value
  for entry in "${_BOOTSTRAP_DEFAULTS[@]}"; do
    key="${entry%%=*}"
    value="${entry#*=}"
    if [[ -z "${!key+x}" ]]; then
      # shellcheck disable=SC2086
      printf -v "$key" '%s' "$value"
    fi
  done

  # Export for child processes.
  local entry2 key2
  for entry2 in "${_BOOTSTRAP_DEFAULTS[@]}"; do
    key2="${entry2%%=*}"
    # shellcheck disable=SC2163
    export "$key2"="${!key2}"
  done

  # Required: at least an admin user.
  if [[ -z "${ADMIN_USER:-}" ]]; then
    die "ADMIN_USER must be set in bootstrap.conf"
  fi
}

bootstrap_config_summary() {
  log_debug "config: HOSTNAME=${HOSTNAME:-} TIMEZONE=${TIMEZONE:-} ADMIN_USER=${ADMIN_USER:-}"
}

# Convenience: resolve a boolean config key. Returns 0 (true) or 1 (false).
bootstrap_config_bool() {
  local key="$1" val="${!key:-}"
  case "${val,,}" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}