#!/usr/bin/env bash
# modules/30-security.sh — Stage 2: SSH hardening, UFW, Fail2Ban, AppArmor, sysctl, auditd.
# Gated by runner_safety_prerequisite(): the runner refuses to enter stage 2
# unless state/20-users.state status=admin_validated.
set -Eeuo pipefail

mod_30_security_description() { echo "SSH hardening, UFW, Fail2Ban, AppArmor, sysctl, auditd"; }
mod_30_security_stage()       { echo "2"; }
mod_30_security_dependencies(){ echo "20-users"; }

SSHD_HARDENING_LINES=(
  "Port ${SSH_PORT:-22}"
  "PermitRootLogin no"
  "PasswordAuthentication no"
  "PubkeyAuthentication yes"
  "ChallengeResponseAuthentication no"
  "KbdInteractiveAuthentication no"
  "PermitEmptyPasswords no"
  "X11Forwarding no"
  "AllowAgentForwarding yes"
  "AllowTcpForwarding yes"
  "MaxAuthTries 3"
  "LoginGraceTime 30"
  "ClientAliveInterval 300"
  "ClientAliveCountMax 2"
  "UsePAM yes"
)

# Curated, kernel-current sysctl set. Each line is justified by an inline comment.
SYSCTL_LINES=(
  "# kernel hardening: pointer and dmesg restrictions"
  "kernel.kptr_restrict = 2"
  "kernel.dmesg_restrict = 1"
  "kernel.yama.ptrace_scope = 2"
  "kernel.randomize_va_space = 2"
  "kernel.sysrq = 0"
  "# network: IPv4 forwarding off (server use), ignore bogus errors, ignore source-routed packets"
  "net.ipv4.ip_forward = 0"
  "net.ipv4.conf.all.rp_filter = 1"
  "net.ipv4.conf.default.rp_filter = 1"
  "net.ipv4.conf.all.accept_source_route = 0"
  "net.ipv4.conf.default.accept_source_route = 0"
  "net.ipv4.conf.all.accept_redirects = 0"
  "net.ipv4.conf.default.accept_redirects = 0"
  "net.ipv4.conf.all.secure_redirects = 0"
  "net.ipv4.conf.default.secure_redirects = 0"
  "net.ipv4.conf.all.send_redirects = 0"
  "net.ipv4.conf.default.send_redirects = 0"
  "net.ipv4.conf.all.log_martians = 1"
  "net.ipv4.icmp_echo_ignore_broadcasts = 1"
  "net.ipv4.icmp_ignore_bogus_error_responses = 1"
  "net.ipv4.tcp_syncookies = 1"
  "# network: IPv6 hardening (modern kernel defaults that still apply)"
  "net.ipv6.conf.all.accept_source_route = 0"
  "net.ipv6.conf.default.accept_source_route = 0"
  "net.ipv6.conf.all.accept_redirects = 0"
  "net.ipv6.conf.default.accept_redirects = 0"
  "# fs: protect hard and soft link handling"
  "fs.protected_hardlinks = 1"
  "fs.protected_symlinks = 1"
)

mod_30_security_check() {
  local f="/etc/ssh/sshd_config"
  [[ -f "$f" ]] || return 1
  grep -q '^PermitRootLogin no$' "$f" || return 1
  grep -q '^PasswordAuthentication no$' "$f" || return 1
  [[ -f /etc/sysctl.d/99-bootstrapx.conf ]] || return 1
  return 0
}

mod_30_security_install() {
  log_info "stage 2: hardening SSH"
  # Backup and patch sshd_config.
  local cfg="/etc/ssh/sshd_config"
  fs_backup_file "$cfg" >/dev/null || true
  for line in "${SSHD_HARDENING_LINES[@]}"; do
    ensure_line "$cfg" "$line"
  done
  # Validate before any restart.
  sshd_validate
  ensure_service_sshd_reload

  log_info "stage 2: configuring firewall (UFW)"
  ensure_package ufw
  # Default policies.
  ensure_line /etc/default/ufw "IPT_DEFAULT_POLICY=\"DROP\""
  ensure_line /etc/ufw/ufw.conf "DEFAULT_INPUT_POLICY=\"DROP\""
  ensure_line /etc/ufw/ufw.conf "DEFAULT_OUTPUT_POLICY=\"ACCEPT\""
  ensure_line /etc/ufw/ufw.conf "DEFAULT_FORWARD_POLICY=\"DROP\""
  # Allow SSH on configured port.
  local port="${SSH_PORT:-22}"
  if ufw status 2>/dev/null | grep -qE "^\s*${port}/tcp"; then
    log_debug "ufw already allows ${port}/tcp"
  else
    log_info "ufw: allowing ${port}/tcp"
    if (( ! BOOTSTRAP_DRY_RUN )); then
      ufw allow "${port}/tcp"
    fi
  fi
  ensure_service_enabled ufw
  # Enable without prompting.
  if (( ! BOOTSTRAP_DRY_RUN )); then
    yes | ufw enable >/dev/null 2>&1 || ufw --force enable
  fi

  if bootstrap_config_bool ENABLE_FAIL2BAN; then
    log_info "stage 2: configuring Fail2Ban"
    ensure_package fail2ban
    ensure_directory /etc/fail2ban/jail.d 0755 root:root
    ensure_file /etc/fail2ban/jail.d/bootstrapx.conf \
$'[sshd]
enabled = true
port = '"${port}"$'
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
findtime = 600
bantime = 3600
'
    ensure_service_enabled fail2ban
    ensure_service_running fail2ban
  fi

  if bootstrap_config_bool ENABLE_APPARMOR; then
    log_info "stage 2: enabling AppArmor"
    ensure_package apparmor apparmor-utils
    ensure_service_enabled apparmor
    ensure_service_running apparmor
    if [[ -d /etc/apparmor.d ]]; then
      ensure_line /etc/apparmor.d/boot_profile "boot_profile=attach"
    fi
  fi

  log_info "stage 2: applying sysctl hardening"
  for line in "${SYSCTL_LINES[@]}"; do
    [[ "$line" =~ ^# ]] && continue
    ensure_line /etc/sysctl.d/99-bootstrapx.conf "$line"
  done
  if (( ! BOOTSTRAP_DRY_RUN )); then
    sysctl --system >/dev/null 2>&1 || true
  fi

  log_info "stage 2: auditd + needrestart"
  ensure_package auditd needrestart
  ensure_service_enabled auditd
  ensure_service_running auditd
  ensure_service_enabled needrestart

  if bootstrap_config_bool ENABLE_AUTO_UPDATES; then
    log_info "stage 2: unattended-upgrades (security only)"
    ensure_package unattended-upgrades apt-listchanges
    if [[ ! -f /etc/apt/apt.conf.d/50unattended-upgrades ]]; then
      ensure_file /etc/apt/apt.conf.d/50unattended-upgrades \
$'Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
'
    fi
    ensure_service_enabled unattended-upgrades
  fi
}

mod_30_security_validate() {
  sshd_validate || return 1
  local cfg="/etc/ssh/sshd_config"
  grep -q '^PermitRootLogin no$' "$cfg" || { log_error "PermitRootLogin no not applied"; return 1; }
  grep -q '^PasswordAuthentication no$' "$cfg" || { log_error "PasswordAuthentication no not applied"; return 1; }
  svc_active ufw || log_warn "ufw not active"
  [[ -f /etc/sysctl.d/99-bootstrapx.conf ]] || { log_error "sysctl file missing"; return 1; }
  return 0
}

mod_30_security_rollback() {
  # Restore backed-up sshd_config and validate.
  sshd_validate || true
  if [[ -e /etc/ssh/sshd_config ]]; then
    local bk
    bk="$(fs_find_latest_backup_for "/etc/ssh/sshd_config")"
    [[ -n "$bk" ]] && fs_restore_backup "$bk" /etc/ssh/sshd_config
  fi
  sshd_validate || true
  sshd_reload_safely || true
}