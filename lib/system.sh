#!/usr/bin/env bash
# lib/system.sh — OS detection, root check, command availability.
# No deps.
set -Eeuo pipefail

bootstrap_system_distro()
{
  local id=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-unknown}"
  fi
  printf '%s\n' "$id"
}

bootstrap_system_version()
{
  local v=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    v="${VERSION_ID:-unknown}"
  fi
  printf '%s\n' "$v"
}

bootstrap_system_arch()
{
  local a
  a="$(uname -m)"
  case "$a" in
    x86_64) printf 'amd64\n' ;;
    aarch64) printf 'arm64\n' ;;
    *) printf '%s\n' "$a" ;;
  esac
}

bootstrap_system_is_root()
{
  ((EUID == 0))
}

bootstrap_system_require_root()
{
  if ! bootstrap_system_is_root; then
    printf 'ERROR: bootstrap must be run as root (use sudo).\n' >&2
    return 1
  fi
}

bootstrap_system_require_cmd()
{
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'ERROR: required command not found: %s\n' "$cmd" >&2
    return 1
  fi
}

bootstrap_system_is_ubuntu()
{
  [[ "$(bootstrap_system_distro)" == "ubuntu" ]]
}

bootstrap_system_is_debian()
{
  [[ "$(bootstrap_system_distro)" == "debian" ]]
}

bootstrap_system_supported()
{
  local d
  d="$(bootstrap_system_distro)"
  if [[ "$d" != "ubuntu" && "$d" != "debian" ]]; then
    printf 'ERROR: unsupported distro: %s (need ubuntu or debian)\n' "$d" >&2
    return 1
  fi
  local v
  v="$(bootstrap_system_version)"
  case "$d" in
    ubuntu) [[ "$v" == "24.04" ]] || {
      printf 'ERROR: ubuntu %s not supported (need 24.04)\n' "$v" >&2
      return 1
    } ;;
    debian) [[ "$v" == "12" ]] || {
      printf 'ERROR: debian %s not supported (need 12)\n' "$v" >&2
      return 1
    } ;;
  esac
  local a
  a="$(uname -m)"
  case "$a" in
    x86_64 | aarch64) ;;
    *)
      printf 'ERROR: unsupported architecture: %s (need x86_64 or aarch64)\n' "$a" >&2
      return 1
      ;;
  esac
}
