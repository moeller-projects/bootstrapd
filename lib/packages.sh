#!/usr/bin/env bash
# lib/packages.sh — apt wrappers used by ensure_package(s) and ensure_repo.
# Deps: log, fs, network.
set -Eeuo pipefail

pkg_installed()
{
  local name="$1"
  dpkg-query -W -f='${Status}' -- "$name" 2>/dev/null |
    grep -q '^install ok installed$'
}

pkg_install()
{
  local name="$1"
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would apt-get install -y $name"
    return 0
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$name"
}

pkg_install_many()
{
  local -a names=()
  while (($#)); do
    names+=("$1")
    shift
  done
  if ((${#names[@]} == 0)); then
    return 0
  fi
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would apt-get install -y ${names[*]}"
    return 0
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${names[@]}"
}

pkg_update_index()
{
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would apt-get update"
    return 0
  fi
  apt-get update
}

pkg_upgrade()
{
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would apt-get -y upgrade"
    return 0
  fi
  DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
}

# pkg_repo_add LINE NAME [SIGNED_BY]  — adds a deb line via "deb822" sources.
# Writes /etc/apt/sources.list.d/<name>.sources and runs apt-get update.
pkg_repo_add()
{
  local line="$1" name="$2" signed_by="${3:-}"
  local path="/etc/apt/sources.list.d/${name}.sources"
  local body=""
  if [[ -n "$signed_by" ]]; then
    body+="Signed-By: ${signed_by}
"
  fi
  body+="Types: deb
"
  body+="URIs: ${line}
"
  body+="Suites: $(bootstrap_system_distro)
"
  body+="Components: main
"
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would write $path and apt-get update"
    return 0
  fi
  fs_backup_file "$path" >/dev/null || true
  fs_atomic_write "$path" "$body"
  register_rollback "$path" "fs_restore_backup <backup> $path"
  apt-get update
}

# pkg_gpg_key URL DEST  — downloads a GPG key to /etc/apt/keyrings/<name>.
pkg_gpg_key_install()
{
  local url="$1" dest="$2"
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would fetch GPG key $url -> $dest"
    return 0
  fi
  fs_mkdir_p /etc/apt/keyrings
  net_download "$url" "$dest" "0644"
}

# pkg_gpg_key_dearmor FILE DEST  — converts ASCII-armored key to binary.
pkg_gpg_key_dearmor()
{
  local src="$1" dest="$2"
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would dearmor $src -> $dest"
    return 0
  fi
  fs_mkdir_p "$(dirname -- "$dest")"
  gpg --dearmor <"$src" >"$dest"
  chmod 0644 "$dest"
}
