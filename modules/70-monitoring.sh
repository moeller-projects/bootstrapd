#!/usr/bin/env bash
# modules/70-monitoring.sh — Stage 6: monitoring tools.
set -Eeuo pipefail

mod_70_monitoring_description()
{
  echo "Monitoring: btop, fastfetch, smartctl, vnstat, iotop, iftop, lm-sensors"
}
mod_70_monitoring_stage()
{
  echo "6"
}
mod_70_monitoring_dependencies()
{
  echo "50-dev"
}

mod_70_monitoring_check()
{
  command -v btop >/dev/null || return 1
  return 0
}

_install_gh_binary()
{
  local repo="$1" asset_pattern="$2" dest_path="$3"
  local tmp
  tmp="$(mktemp -d)"
  local url="https://github.com/${repo}/releases/latest/download/${asset_pattern}"
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would fetch $url"
    rm -rf "$tmp"
    return 0
  fi
  curl --fail --location --silent --show-error --connect-timeout 15 --max-time 600 \
    -o "${tmp}/artifact" -- "$url" || {
    rm -rf "$tmp"
    return 1
  }
  install -m 0755 "${tmp}/artifact" "$dest_path"
  rm -rf "$tmp"
}

mod_70_monitoring_install()
{
  ensure_packages btop vnstat iotop lm-sensors smartmontools

  # fastfetch is in Debian bookworm-backports / Ubuntu 24.04 universe.
  if ! command -v fastfetch >/dev/null 2>&1; then
    if ((!BOOTSTRAP_DRY_RUN)); then
      ensure_packages fastfetch || log_warn "fastfetch not in repos; skip"
    fi
  fi

  # iftop is in repos; ensure installed.
  ensure_packages iftop

  # smartd: enable periodic short self-tests.
  ensure_service_enabled smartd 2>/dev/null || true
  if [[ -f /etc/smartd.conf ]]; then
    if ! grep -qF "DEVICESCAN -a -o on -S on -n standby,q -W 4,35,40" /etc/smartd.conf; then
      ensure_line /etc/smartd.conf \
        'DEVICESCAN -a -o on -S on -n standby,q -W 4,35,40'
      ensure_service_running smartd 2>/dev/null || true
    fi
  fi

  # vnstat: enable collection.
  ensure_service_enabled vnstat

  # lm-sensors: detect sensors non-interactively.
  if ((!BOOTSTRAP_DRY_RUN)); then
    yes | sensors-detect --auto >/dev/null 2>&1 || true
  fi
}

mod_70_monitoring_validate()
{
  command -v btop >/dev/null || {
    log_error "btop missing"
    return 1
  }
  command -v smartctl >/dev/null || {
    log_error "smartctl missing"
    return 1
  }
  command -v vnstat >/dev/null || {
    log_error "vnstat missing"
    return 1
  }
  return 0
}

mod_70_monitoring_rollback()
{
  :
}
