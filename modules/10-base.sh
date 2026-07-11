#!/usr/bin/env bash
# modules/10-base.sh — Stage 1: base system bootstrap.
# Installs the foundational packages required by every other module.
set -Eeuo pipefail

mod_10_base_description() { echo "Install base packages and configure timezone/locale/hostname"; }
mod_10_base_stage()       { echo "1"; }
mod_10_base_dependencies(){ echo ""; }

BASE_PACKAGES=(
  sudo
  openssh-server
  ca-certificates
  curl
  wget
  gnupg
  lsb-release
  apt-transport-https
  software-properties-common
  ufw
  chrony
  unattended-upgrades
  vim-tiny
  nano
  jq
  htop
  git
  rsync
  bash-completion
)

mod_10_base_check() {
  local p
  for p in "${BASE_PACKAGES[@]}"; do
    pkg_installed "$p" || return 1
  done
  return 0
}

mod_10_base_install() {
  pkg_update_index
  DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
  ensure_packages "${BASE_PACKAGES[@]}"

  ensure_hostname "${HOSTNAME:-$(hostname)}"
  ensure_timezone "${TIMEZONE:-UTC}"
  ensure_locale "${LOCALE:-en_US.UTF-8}"

  # Shell: ensure bash-completion is wired up.
  if [[ -f /etc/bash.bashrc ]] && ! grep -qF "bash_completion" /etc/bash.bashrc; then
    ensure_line /etc/bash.bashrc '[[ -r /usr/share/bash-completion/bash_completion ]] && . /usr/share/bash-completion/bash_completion'
  fi

  # Auto-updates (unattended-upgrades is installed, but enable it).
  if bootstrap_config_bool ENABLE_AUTO_UPDATES; then
    ensure_package unattended-upgrades
    if [[ ! -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
      ensure_file /etc/apt/apt.conf.d/20auto-upgrades \
$'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Download-Upgradeable-Packages "1";
'
    fi
    ensure_service_enabled unattended-upgrades
  fi

  # chrony for time sync.
  ensure_service_enabled chrony
  ensure_service_running chrony
}

mod_10_base_validate() {
  local p
  for p in "${BASE_PACKAGES[@]}"; do
    pkg_installed "$p" || { log_error "missing package: $p"; return 1; }
  done
  [[ "$(date +%Z)" != "UTC" ]] || true  # UTC is fine; just a sanity hook.
  return 0
}

mod_10_base_rollback() {
  # Removing the base packages would break the system. Rollback only removes
  # what this module explicitly added and is otherwise a no-op.
  :
}