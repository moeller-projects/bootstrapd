#!/usr/bin/env bash
# modules/50-dev.sh — Stage 3: language runtimes (Node, Bun, Python, .NET).
# Git/GitHub CLI/delta/Git LFS live in 45-git.sh.
# Shell tooling (zsh, starship, fzf, zoxide, bat, eza, ripgrep, fd, jq, yq,
# tmux, direnv, fastfetch, btop) lives in 55-shell.sh.
#
# This module's job is purely: install the language toolchains and let users
# opt into per-tool versions.
set -Eeuo pipefail

mod_50_dev_description()
{
  echo "Language runtimes: Node LTS, Bun, Python, uv, pipx, .NET SDK"
}
mod_50_dev_stage()
{
  echo "3"
}
mod_50_dev_dependencies()
{
  echo "30-security"
}

mod_50_dev_check()
{
  command -v git >/dev/null || return 1 # 45-git should have installed it
  command -v node >/dev/null || return 1
  return 0
}

_install_gh_binary()
{
  # _install_gh_binary REPO ASSET DEST
  local repo="$1" asset="$2" dest="$3"
  local tmp url
  tmp="$(mktemp -d)"
  url="https://github.com/${repo}/releases/latest/download/${asset}"
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would download $url -> $dest"
    rm -rf "$tmp"
    return 0
  fi
  if curl --fail --location --silent --show-error \
    --connect-timeout 15 --max-time 600 \
    -o "${tmp}/artifact" -- "$url"; then
    install -m 0755 "${tmp}/artifact" "$dest"
  else
    log_warn "download failed: $url"
  fi
  rm -rf "$tmp"
}

mod_50_dev_install()
{
  # ---------- Node.js (NodeSource apt repo) ----------
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
    if ((!BOOTSTRAP_DRY_RUN)); then
      if command -v npm >/dev/null; then
        npm install -g bun 2>/dev/null || log_warn "bun npm install failed; install manually"
      else
        local arch
        arch="$(uname -m)"
        case "$arch" in
          x86_64) arch=x64 ;;
          aarch64) arch=aarch64 ;;
        esac
        _install_gh_binary "oven-sh/bun" "bun-linux-${arch}.zip" /tmp/bun.zip
        if [[ -f /tmp/bun.zip ]]; then
          mkdir -p /usr/local/bun
          unzip -o -q /tmp/bun.zip -d /usr/local/bun
          ln -sf /usr/local/bun/bun /usr/local/bin/bun
          rm -f /tmp/bun.zip
        fi
      fi
    fi
  fi

  # ---------- Python (system) + uv + pipx + ruff + black ----------
  ensure_packages python3 python3-venv python3-pip python3-dev
  ensure_packages pipx ruff black

  if ! command -v uv >/dev/null 2>&1; then
    log_info "installing uv"
    if ((!BOOTSTRAP_DRY_RUN)); then
      if curl --fail --location --silent --show-error \
        --connect-timeout 15 --max-time 300 \
        https://astral.sh/uv/install.sh | env INSTALLER_NO_MODIFY_PATH=1 sh; then
        # Move to /usr/local/bin for system-wide use.
        if [[ -f "$HOME/.local/bin/uv" ]]; then
          install -m 0755 "$HOME/.local/bin/uv" /usr/local/bin/uv
        elif [[ -f /root/.local/bin/uv ]]; then
          install -m 0755 /root/.local/bin/uv /usr/local/bin/uv
        fi
      else
        log_warn "uv install failed"
      fi
    fi
  fi

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

}

mod_50_dev_validate()
{
  command -v node >/dev/null || {
    log_error "node missing"
    return 1
  }
  command -v python3 >/dev/null || {
    log_error "python3 missing"
    return 1
  }
  command -v dotnet >/dev/null || log_warn "dotnet not installed"
  command -v bun >/dev/null || log_warn "bun not installed"
  command -v uv >/dev/null || log_warn "uv not installed"
  return 0
}

mod_50_dev_rollback()
{
  :
}
