#!/usr/bin/env bash
# lib/network.sh — connectivity checks and downloads.
# Deps: log.
set -Eeuo pipefail

# Wait up to N seconds for the network to come up.
net_wait_online()
{
  local seconds="${1:-30}"
  local i host="1.1.1.1"
  for ((i = 0; i < seconds; i++)); do
    if ping -c1 -W2 "$host" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

net_dns_resolves()
{
  local host="$1"
  getent hosts "$host" >/dev/null 2>&1
}

# net_download URL DEST [mode]
net_download()
{
  local url="$1" dest="$2" mode="${3:-}"
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would download $url -> $dest"
    return 0
  fi
  fs_mkdir_p "$(dirname -- "$dest")"
  curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
    --connect-timeout 15 --max-time 600 -o "$dest" -- "$url"
  if [[ -n "$mode" ]]; then
    chmod "$mode" -- "$dest"
  fi
}

# net_port_listening PORT  — true if anything is listening on the local port.
net_port_listening()
{
  local port="$1"
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -E "(^|:)${port}$" >/dev/null
}

# net_tcp_probe HOST PORT  — true if HOST:PORT accepts a TCP connection within 5s.
net_tcp_probe()
{
  local host="$1" port="$2"
  timeout 5 bash -c "exec 3<>/dev/tcp/${host}/${port}" >/dev/null 2>&1
}
