#!/usr/bin/env bash
# lib/doctor.sh — diagnostics: produces human-readable and JSON reports.
# Deps: log, fs, system, services, network, packages, users, templates, config, ensure.
set -Eeuo pipefail

DOCTOR_JSON="${BOOTSTRAP_STATE:-/tmp}/doctor.json"

# _doctor_check NAME COMMAND  → runs COMMAND, captures pass/fail + output.
# The COMMAND string is evaluated in a subshell, so the caller must escape
# any characters that would otherwise be subject to shell expansion.
_doctor_check()
{
  local name="$1" cmd="$2"
  local out rc=0
  out="$(eval "$cmd" 2>&1)" || rc=$?
  if ((rc == 0)); then
    printf 'OK    %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name"
    [[ -n "$out" ]] && printf '      %s\n' "$out" | head -5
  fi
  printf '%s\t%s\t%s\n' "$name" "$rc" "${out//$'\n'/ | }"
}

# Self-contained resource checks. These are defined as functions (not embedded
# in strings) so the awk scripts can use $1 / $2 without bash re-interpreting them.

_doctor_check_disk()
{
  local avail_g
  avail_g="$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')"
  [[ "$avail_g" =~ ^[0-9]+$ ]] && ((avail_g >= 5))
}

_doctor_check_memory()
{
  local mem
  mem="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
  ((mem >= 1024))
}

_doctor_check_swap()
{
  local swap
  swap="$(awk '/SwapTotal/ {print $2}' /proc/meminfo)"
  ((swap > 0))
}

_doctor_check_gpu()
{
  [[ -e /dev/nvidia0 ]] || {
    command -v lspci >/dev/null && lspci 2>/dev/null | grep -qi nvidia
  }
}

_doctor_check_time_synced()
{
  timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -qx yes
}

_doctor_check_agent_linger()
{
  local user="${1:-agent}"
  loginctl show-user "$user" -p Linger --value 2>/dev/null | grep -qx yes
}

doctor_run()
{
  local json="${DOCTOR_JSON_OUTPUT:-0}"
  bootstrap_config_load
  local report=""

  report+=$'\n'"== BootstrapX Doctor =="

  report+=$'\n\n-- system --'
  report+=$'\n'
  report+="$(_doctor_check 'os' 'bootstrap_system_supported')"
  report+=$'\n'
  report+="$(_doctor_check 'root' 'bootstrap_system_is_root')"
  report+=$'\n'
  report+="$(_doctor_check 'arch' '[[ "$(uname -m)" == "x86_64" || "$(uname -m)" == "aarch64" ]]')"

  report+=$'\n\n-- network --'
  report+=$'\n'
  report+="$(_doctor_check 'internet' 'curl -fsS --connect-timeout 5 https://1.1.1.1 -o /dev/null')"
  report+=$'\n'
  report+="$(_doctor_check 'dns' 'getent hosts deb.debian.org || getent hosts archive.ubuntu.com')"
  report+=$'\n'
  report+="$(_doctor_check 'time synced' '_doctor_check_time_synced')"

  report+=$'\n\n-- users (least-privilege model) --'
  report+=$'\n'
  report+="$(_doctor_check "user $ADMIN_USER exists" "id -u $ADMIN_USER")"
  report+=$'\n'
  report+="$(_doctor_check "$ADMIN_USER has authorized_keys" "[[ \$(ssh_user_keycount $ADMIN_USER) -gt 0 ]]")"
  report+=$'\n'
  report+="$(_doctor_check "$ADMIN_USER has sudo" "sudo -n -u $ADMIN_USER true")"
  report+=$'\n'
  report+="$(_doctor_check "$AGENT_USER exists" "id -u $AGENT_USER")"
  report+=$'\n'
  report+="$(_doctor_check "$AGENT_USER has nologin shell" '
    shell=$(getent passwd "$1" | cut -d: -f7)
    [[ "$shell" == "/usr/sbin/nologin" || "$shell" == "/bin/false" ]]
  ' "$AGENT_USER")"
  report+=$'\n'
  report+="$(_doctor_check "$AGENT_USER password locked" "passwd -S $AGENT_USER | grep -qE '^[^ ]+ L '")"
  report+=$'\n'
  report+="$(_doctor_check "$AGENT_USER has no authorized_keys" '! [[ -f "$(getent passwd "$1" | cut -d: -f6)/.ssh/authorized_keys" ]]' "$AGENT_USER")"
  report+=$'\n'
  report+="$(_doctor_check "$AGENT_USER cannot sudo" "! sudo -n -u $AGENT_USER true 2>/dev/null")"

  report+=$'\n\n-- filesystem --'
  report+=$'\n'
  report+="$(_doctor_check '/srv exists' '[[ -d /srv ]]')"
  report+=$'\n'
  report+="$(_doctor_check '/srv/workspace exists' '[[ -d /srv/workspace ]]')"
  report+=$'\n'
  report+="$(_doctor_check '/srv/agent exists' '[[ -d /srv/agent ]]')"
  report+=$'\n'
  report+="$(_doctor_check '/srv/models exists' '[[ -d /srv/models ]]')"

  report+=$'\n\n-- services --'
  report+=$'\n'
  report+="$(_doctor_check 'sshd installed' 'command -v sshd')"
  report+=$'\n'
  report+="$(_doctor_check 'sshd config valid' 'sshd -t')"
  report+=$'\n'
  report+="$(_doctor_check 'sshd running' 'svc_active ssh || svc_active sshd')"

  if bootstrap_config_bool ENABLE_FAIL2BAN; then
    report+=$'\n'
    report+="$(_doctor_check 'fail2ban enabled' 'svc_enabled fail2ban')"
  fi

  if bootstrap_config_bool ENABLE_APPARMOR; then
    report+=$'\n'
    report+="$(_doctor_check 'apparmor enabled' 'aa-enabled')"
  fi

  report+=$'\n\n-- containers --'
  if bootstrap_config_bool ENABLE_PODMAN; then
    report+=$'\n'
    report+="$(_doctor_check 'podman installed' 'command -v podman')"
    report+=$'\n'
    report+="$(_doctor_check 'podman runs rootless' "su - $ADMIN_USER -s /bin/bash -c 'podman info >/dev/null 2>&1'")"
  fi

  report+=$'\n\n-- git --'
  report+=$'\n'
  report+="$(_doctor_check 'git' 'command -v git')"
  if bootstrap_config_bool ENABLE_GITHUB_CLI; then
    report+=$'\n'
    report+="$(_doctor_check 'gh' 'command -v gh')"
  fi

  report+=$'\n\n-- developer tools --'
  report+=$'\n'
  report+="$(_doctor_check 'node' 'command -v node')"
  report+=$'\n'
  report+="$(_doctor_check 'bun' 'command -v bun')"
  report+=$'\n'
  report+="$(_doctor_check 'python3' 'command -v python3')"
  report+=$'\n'
  report+="$(_doctor_check 'uv' 'command -v uv')"
  report+=$'\n'
  report+="$(_doctor_check 'dotnet' 'command -v dotnet')"
  report+=$'\n'
  report+="$(_doctor_check 'pwsh' 'command -v pwsh')"
  report+=$'\n'
  report+="$(_doctor_check 'zsh' 'command -v zsh')"
  report+=$'\n'
  report+="$(_doctor_check 'starship' 'command -v starship')"
  report+=$'\n'
  report+="$(_doctor_check 'btop' 'command -v btop')"

  report+=$'\n\n-- ai tools --'
  if bootstrap_config_bool ENABLE_PI; then
    report+=$'\n'
    report+="$(_doctor_check 'pi' 'command -v pi')"
  fi
  if bootstrap_config_bool ENABLE_CODEX; then
    report+=$'\n'
    report+="$(_doctor_check 'codex' 'command -v codex')"
  fi
  if bootstrap_config_bool ENABLE_CLAUDE; then
    report+=$'\n'
    report+="$(_doctor_check 'claude' 'command -v claude')"
  fi
  if bootstrap_config_bool ENABLE_OPENCLAW; then
    report+=$'\n'
    report+="$(_doctor_check 'openclaw' 'command -v openclaw || [[ -d /opt/openclaw ]]')"
  fi
  # Agent user services
  if id "$AGENT_USER" >/dev/null 2>&1; then
    report+=$'\n'
    report+="$(_doctor_check "$AGENT_USER has linger enabled" "_doctor_check_agent_linger $AGENT_USER")"
  fi

  report+=$'\n\n-- resources --'
  report+=$'\n'
  report+="$(_doctor_check 'disk free >=5G' '_doctor_check_disk')"
  report+=$'\n'
  report+="$(_doctor_check 'memory >=1G' '_doctor_check_memory')"
  report+=$'\n'
  report+="$(_doctor_check 'swap present' '_doctor_check_swap')"

  report+=$'\n\n-- hardware --'
  report+=$'\n'
  report+="$(_doctor_check 'GPU detected (nvidia)' '_doctor_check_gpu')"

  printf '%s\n' "$report"

  if [[ "$json" == "1" ]]; then
    doctor_to_json "$report" >"$DOCTOR_JSON"
    printf '\nJSON report written to %s\n' "$DOCTOR_JSON"
  fi
}

doctor_to_json()
{
  local rpt="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    printf '{"error":"python3 required for json report"}\n'
    return 0
  fi
  python3 - "$rpt" <<'PY'
import sys, json, re
text = sys.argv[1]
checks = []
for line in text.splitlines():
    m = re.match(r'^(OK|FAIL)\s+(\S+)\s*$', line)
    if m:
        checks.append({'status': m.group(1).lower(), 'name': m.group(2)})
summary = {
  'ok': sum(1 for c in checks if c['status'] == 'ok'),
  'fail': sum(1 for c in checks if c['status'] == 'fail'),
}
print(json.dumps({'summary': summary, 'checks': checks}, indent=2))
PY
}
