#!/usr/bin/env bash
# lib/services.sh — systemctl wrappers plus sshd validation.
# Deps: log, fs.
set -Eeuo pipefail

svc_active()  { systemctl is-active --quiet -- "$1"; }
svc_enabled() { [[ "$(systemctl is-enabled -- "$1" 2>/dev/null)" == "enabled" ]]; }
svc_failed()  { systemctl is-failed --quiet -- "$1"; }

svc_enable() {
  local name="$1"
  if svc_enabled "$name"; then
    return 0
  fi
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would systemctl enable $name"
    return 0
  fi
  systemctl enable -- "$name"
}

svc_disable() {
  local name="$1"
  if ! svc_active "$name" && ! svc_enabled "$name"; then
    return 0
  fi
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would systemctl disable --now $name"
    return 0
  fi
  systemctl disable --now -- "$name" || true
}

svc_start() {
  local name="$1"
  if svc_active "$name"; then
    return 0
  fi
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would systemctl start $name"
    return 0
  fi
  systemctl start -- "$name"
}

svc_stop() {
  local name="$1"
  if ! svc_active "$name"; then
    return 0
  fi
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would systemctl stop $name"
    return 0
  fi
  systemctl stop -- "$name" || true
}

svc_reload() {
  local name="$1"
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would systemctl reload-or-restart $name"
    return 0
  fi
  systemctl reload-or-restart -- "$name"
}

svc_restart() {
  local name="$1"
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would systemctl restart $name"
    return 0
  fi
  systemctl restart -- "$name"
}

# sshd_validate  — runs `sshd -t` and dies on failure.
sshd_validate() {
  if ! command -v sshd >/dev/null; then
    log_warn "sshd not installed; skipping sshd -t"
    return 0
  fi
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would sshd -t"
    return 0
  fi
  if ! sshd -t; then
    die "sshd -t failed; refusing to restart sshd. Inspect /etc/ssh/sshd_config."
  fi
  log_debug "sshd -t ok"
}

# sshd_reload_safely  — validate, then reload-or-restart.
sshd_reload_safely() {
  sshd_validate
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would reload ssh"
    return 0
  fi
  systemctl reload-or-restart ssh sshd 2>/dev/null || systemctl reload-or-restart ssh
}

# sshd_in_backup_service NAME
# Some sshd units have a different name (ssh on Debian, sshd on Ubuntu). Returns whichever is present.
sshd_unit_name() {
  systemctl list-unit-files --type=service --no-legend 2>/dev/null \
    | awk '{print $1}' \
    | grep -E '^(ssh|sshd)\.service$' \
    | head -1 \
    | sed 's/\.service$//'
}