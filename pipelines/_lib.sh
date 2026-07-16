#!/usr/bin/env bash
# pipelines/_lib.sh — shared helpers for all pipeline scripts.
set -Eeuo pipefail

# Resolve the repo root (parent of this file's directory).
PIPELINES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$PIPELINES_DIR/.." && pwd)"
export PIPELINES_DIR REPO_ROOT

# Local tool install — populate $REPO_ROOT/pipelines/.tools/ on demand.
TOOLS_DIR="$PIPELINES_DIR/.tools"
mkdir -p "$TOOLS_DIR"

# Add local tool dir + user's pip/npm bins to PATH so command -v finds them.
export PATH="$TOOLS_DIR:$HOME/.local/bin:$PATH"

# ANSI colour helpers (only when stderr is a TTY).
if [[ -t 2 ]]; then
  _C_RED=$'\033[31m'
  _C_GRN=$'\033[32m'
  _C_YEL=$'\033[33m'
  _C_BLU=$'\033[34m'
  _C_DIM=$'\033[2m'
  _C_RST=$'\033[0m'
else
  _C_RED="" _C_GRN="" _C_YEL="" _C_BLU="" _C_DIM="" _C_RST=""
fi

step()
{
  printf '%s==>%s %s\n' "$_C_BLU" "$_C_RST" "$*" >&2
}
ok()
{
  printf '%s  ok%s  %s\n' "$_C_GRN" "$_C_RST" "$*" >&2
}
warn()
{
  printf '%s warn%s %s\n' "$_C_YEL" "$_C_RST" "$*" >&2
}
err()
{
  printf '%s err%s  %s\n' "$_C_RED" "$_C_RST" "$*" >&2
}
dim()
{
  printf '%s      %s%s\n' "$_C_DIM" "$*" "$_C_RST" >&2
}

die()
{
  err "$@"
  exit 1
}

# tool_path TOOL
# Echo the absolute path to TOOL, downloading it into TOOLS_DIR if needed.
# Supported tools: shellcheck, shfmt, bats, yamllint, markdownlint.
tool_path()
{
  local tool="$1"
  case "$tool" in
    shellcheck)
      if command -v shellcheck >/dev/null 2>&1; then
        command -v shellcheck
        return
      fi
      _install_shellcheck
      ;;
    shfmt)
      if command -v shfmt >/dev/null 2>&1; then
        command -v shfmt
        return
      fi
      _install_shfmt
      ;;
    bats)
      if command -v bats >/dev/null 2>&1; then
        command -v bats
        return
      fi
      _install_bats
      ;;
    yamllint)
      if command -v yamllint >/dev/null 2>&1; then
        command -v yamllint
        return
      fi
      _install_yamllint
      ;;
    markdownlint)
      if command -v markdownlint >/dev/null 2>&1; then
        command -v markdownlint
        return
      fi
      _install_markdownlint
      ;;
    *)
      die "unknown tool: $tool"
      ;;
  esac
}

_install_shellcheck()
{
  local dest="$TOOLS_DIR/shellcheck"
  if [[ ! -x "$dest" ]]; then
    step "installing shellcheck into $TOOLS_DIR"
    local tmp
    tmp="$(mktemp -d)"
    if curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz" \
      -o "$tmp/sc.tar.xz"; then
      tar -xJf "$tmp/sc.tar.xz" -C "$tmp"
      install -m 0755 "$tmp/shellcheck-v0.10.0/shellcheck" "$dest"
    else
      die "shellcheck download failed"
    fi
    rm -rf "$tmp"
  fi
  printf '%s\n' "$dest"
}

_install_shfmt()
{
  local dest="$TOOLS_DIR/shfmt"
  if [[ ! -x "$dest" ]]; then
    step "installing shfmt into $TOOLS_DIR"
    local arch
    arch="$(uname -m)"
    case "$arch" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
    if ! curl -fsSL "https://github.com/mvdan/sh/releases/download/v3.10.0/shfmt_v3.10.0_linux_${arch}" \
      -o "$dest"; then
      die "shfmt download failed"
    fi
    chmod +x "$dest"
  fi
  printf '%s\n' "$dest"
}

_install_bats()
{
  local prefix="$TOOLS_DIR/bats-prefix"
  local dest="$TOOLS_DIR/bats"
  if [[ ! -x "$prefix/bin/bats" ]]; then
    step "installing bats into $prefix"
    local tmp
    tmp="$(mktemp -d)"
    if curl -fsSL "https://github.com/bats-core/bats-core/archive/refs/heads/master.tar.gz" \
      -o "$tmp/bats.tgz"; then
      tar -xzf "$tmp/bats.tgz" -C "$tmp"
      bash "$tmp/bats-core-master/install.sh" "$prefix" >/dev/null
    else
      die "bats download failed"
    fi
    rm -rf "$tmp"
  fi
  cat >"$dest" <<EOF
#!/usr/bin/env bash
exec "$prefix/bin/bats" "\$@"
EOF
  chmod 0755 "$dest"
  printf '%s\n' "$dest"
}

_install_yamllint()
{
  local pip_cmd=()
  if command -v pip3 >/dev/null 2>&1; then
    pip_cmd=(pip3)
  elif command -v python3 >/dev/null 2>&1 && python3 -m pip --version >/dev/null 2>&1; then
    pip_cmd=(python3 -m pip)
  else
    die "pip3/python3-pip not available; install yamllint manually"
  fi
  step "installing yamllint via ${pip_cmd[*]} --user"
  "${pip_cmd[@]}" install --user --break-system-packages --quiet yamllint || die "pip install yamllint failed"
  hash -r
  command -v yamllint || die "yamllint not on PATH after install"
}

_install_markdownlint()
{
  local prefix="$TOOLS_DIR/markdownlint"
  local bin="$prefix/node_modules/.bin/markdownlint"
  if [[ ! -x "$bin" ]]; then
    step "installing markdownlint-cli into $prefix"
    mkdir -p "$prefix"
    npm install --prefix "$prefix" markdownlint-cli >/dev/null 2>&1 || die "npm install markdownlint-cli failed"
  fi
  printf '%s\n' "$bin"
}

# All .sh files in the repo (excluding .git, pipelines/.tools, state).
sh_files()
{
  find "$REPO_ROOT" \
    \( -path "$REPO_ROOT/.git" -o -path "$REPO_ROOT/pipelines/.tools" -o -path "$REPO_ROOT/state/backups" \) -prune \
    -o -type f -name '*.sh' -print | sort
}

# All markdown files.
md_files()
{
  find "$REPO_ROOT" \
    \( -path "$REPO_ROOT/.git" -o -path "$REPO_ROOT/pipelines/.tools" -o -path "$REPO_ROOT/state/backups" \) -prune \
    -o -type f -name '*.md' -print | sort
}

# All yaml files (workflows + module manifests if any).
yml_files()
{
  find "$REPO_ROOT" \
    \( -path "$REPO_ROOT/.git" -o -path "$REPO_ROOT/pipelines/.tools" -o -path "$REPO_ROOT/state/backups" \) -prune \
    -o -type f \( -name '*.yml' -o -name '*.yaml' \) -print | sort
}
