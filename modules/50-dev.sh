#!/usr/bin/env bash
# modules/50-dev.sh — Stage 3: developer toolchain (git, node, bun, python, .NET, pwsh).
set -Eeuo pipefail

mod_50_dev_description() { echo "Developer toolchain: git, gh, node, bun, python, .NET, PowerShell"; }
mod_50_dev_stage()       { echo "3"; }
mod_50_dev_dependencies(){ echo "30-security"; }

mod_50_dev_check() {
  command -v git >/dev/null || return 1
  command -v node >/dev/null || return 1
  return 0
}

_install_gh_release() {
  # _install_gh_release REPO BASENAME DEST
  local repo="$1" basename="$2" dest="$3"
  local tmp url
  tmp="$(mktemp -d)"
  url="https://github.com/${repo}/releases/latest/download/${basename}"
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would download $url -> $dest"
    rm -rf "$tmp"
    return 0
  fi
  curl --fail --location --silent --show-error \
    --connect-timeout 15 --max-time 600 \
    -o "${tmp}/artifact" -- "$url" || { log_warn "download failed: $url"; rm -rf "$tmp"; return 1; }
  install -m 0755 "${tmp}/artifact" "$dest"
  rm -rf "$tmp"
}

mod_50_dev_install() {
  local admin="${ADMIN_USER:-admin}"

  # ---------- git + gh + delta + lfs ----------
  ensure_packages git git-lfs
  if bootstrap_config_bool ENABLE_GITHUB_CLI; then
    ensure_packages gh
  fi
  # delta is not in Debian/Ubuntu repos; install from GitHub release when missing.
  if ! command -v delta >/dev/null 2>&1; then
    log_info "installing delta (git diff highlighter)"
    _install_gh_release "dandavison/delta" \
      "delta-$(uname -m)-unknown-linux-gnu.tar.gz" /tmp/delta.tgz || true
    if [[ -f /tmp/delta.tgz ]]; then
      tar -xzf /tmp/delta.tgz -C /tmp delta 2>/dev/null \
        && install -m 0755 /tmp/delta /usr/local/bin/delta \
        && rm -f /tmp/delta /tmp/delta.tgz
    fi
  fi

  # git global config (per-user; applied to admin via sudo -u).
  if id "$admin" >/dev/null 2>&1; then
    sudo -u "$admin" HOME="$(getent passwd "$admin" | cut -d: -f6)" \
      git config --global init.defaultBranch main
    sudo -u "$admin" HOME="$(getent passwd "$admin" | cut -d: -f6)" \
      git config --global core.autocrlf input
    sudo -u "$admin" HOME="$(getent passwd "$admin" | cut -d: -f6)" \
      git config --global pull.rebase true
    sudo -u "$admin" HOME="$(getent passwd "$admin" | cut -d: -f6)" \
      git config --global rerere.enabled true
    sudo -u "$admin" HOME="$(getent passwd "$admin" | cut -d: -f6)" \
      git config --global safe.directory '*'
    if command -v delta >/dev/null; then
      sudo -u "$admin" HOME="$(getent passwd "$admin" | cut -d: -f6)" \
        git config --global core.pager delta
      sudo -u "$admin" HOME="$(getent passwd "$admin" | cut -d: -f6)" \
        git config --global interactive.diffFilter 'delta --color-only'
    fi
    sudo -u "$admin" HOME="$(getent passwd "$admin" | cut -d: -f6)" \
      git lfs install 2>/dev/null || true
  fi

  # ---------- Node.js (NodeSource) ----------
  local node_major="${NODE_VERSION:-22}"
  if ! command -v node >/dev/null 2>&1 || [[ "$(node -v 2>/dev/null | cut -d. -f1 | tr -d v)" != "$node_major" ]]; then
    log_info "installing Node.js ${node_major}.x via NodeSource"
    ensure_gpg_key "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" \
      /etc/apt/keyrings/nodesource.gpg
    ensure_repo "https://deb.nodesource.com/node_${node_major}.x" nodesource-node \
      /etc/apt/keyrings/nodesource.gpg
    ensure_package nodejs
  fi

  # ---------- Bun ----------
  if ! command -v bun >/dev/null 2>&1; then
    log_info "installing Bun"
    _install_gh_release "oven-sh/bun" "bun-linux-$(uname -m | sed 's/aarch64/aarch64/;s/x86_64/x64/').zip" \
      /tmp/bun.zip
    if [[ -f /tmp/bun.zip ]]; then
      if (( ! BOOTSTRAP_DRY_RUN )); then
        mkdir -p /usr/local/bun
        unzip -o -q /tmp/bun.zip -d /usr/local/bun
        ln -sf /usr/local/bun/bun /usr/local/bin/bun
        rm -f /tmp/bun.zip
      fi
    fi
  fi

  # ---------- Python (system + uv + pipx + ruff + black) ----------
  ensure_packages python3 python3-venv python3-pip python3-dev
  # uv: Astral's installer.
  if ! command -v uv >/dev/null 2>&1; then
    log_info "installing uv"
    if (( ! BOOTSTRAP_DRY_RUN )); then
      curl --fail --location --silent --show-error \
        --connect-timeout 15 --max-time 300 \
        https://astral.sh/uv/install.sh | env INSTALLER_NO_MODIFY_PATH=1 sh
      install -m 0755 "$HOME/.local/bin/uv" /usr/local/bin/uv 2>/dev/null || true
      install -m 0755 /root/.local/bin/uv /usr/local/bin/uv 2>/dev/null || true
    fi
  fi
  ensure_packages pipx ruff black

  # ---------- .NET SDK ----------
  local channel="${DOTNET_CHANNEL:-9.0}"
  if ! command -v dotnet >/dev/null 2>&1; then
    log_info "installing .NET SDK ${channel}"
    ensure_gpg_key "https://packages.microsoft.com/keys/microsoft.asc" \
      /etc/apt/keyrings/microsoft.gpg
    ensure_repo "https://packages.microsoft.com/debian/12/prod" \
      "dotnet-${channel}" /etc/apt/keyrings/microsoft.gpg
    ensure_package "dotnet-sdk-${channel}"
  fi

  # ---------- PowerShell ----------
  if ! command -v pwsh >/dev/null 2>&1; then
    log_info "installing PowerShell"
    ensure_gpg_key "https://packages.microsoft.com/keys/microsoft.asc" \
      /etc/apt/keyrings/microsoft.gpg
    ensure_repo "https://packages.microsoft.com/debian/12/prod" \
      powershell /etc/apt/keyrings/microsoft.gpg
    ensure_package powershell
  fi

  # ---------- Workspace directories for the admin user ----------
  if id "$admin" >/dev/null 2>&1; then
    local home
    home="$(getent passwd "$admin" | cut -d: -f6)"
    for sub in workspace repos cache logs agents; do
      ensure_directory "$home/$sub" 0755 "$admin:$admin"
    done
  fi
}

mod_50_dev_validate() {
  command -v git >/dev/null || { log_error "git missing"; return 1; }
  command -v node >/dev/null || { log_error "node missing"; return 1; }
  command -v python3 >/dev/null || { log_error "python3 missing"; return 1; }
  command -v dotnet >/dev/null || log_warn "dotnet not installed"
  command -v pwsh >/dev/null || log_warn "pwsh not installed"
  command -v bun >/dev/null || log_warn "bun not installed"
  command -v uv >/dev/null || log_warn "uv not installed"
  return 0
}

mod_50_dev_rollback() {
  :
}