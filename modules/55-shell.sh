#!/usr/bin/env bash
# modules/55-shell.sh — Stage 3: modern shell environment for the admin user.
#
# Tools installed:
#   zsh, starship, fzf, zoxide, bat, eza, ripgrep, fd, jq, yq, delta, tmux,
#   direnv, fastfetch, btop
#
# All per-user config lives under admin's home. Each tool's config is written
# only if the file is missing OR differs from what we manage — user edits
# inside the managed block survive a re-run.
set -Eeuo pipefail

mod_55_shell_description()
{
  echo "Modern shell: zsh, starship, fzf, zoxide, bat, eza, ripgrep, fd, jq, yq, delta, tmux, direnv, fastfetch, btop"
}
mod_55_shell_stage()
{
  echo "3"
}
mod_55_shell_dependencies()
{
  echo "30-security"
}

SHELL_PACKAGES_APT=(
  zsh tmux jq btop
)
SHELL_PACKAGES_EXTRA=(
  fzf zoxide bat ripgrep fd-find direnv
)

mod_55_shell_check()
{
  command -v zsh >/dev/null || return 1
  command -v starship >/dev/null || return 1
  return 0
}

_install_starship()
{
  if command -v starship >/dev/null 2>&1; then
    return 0
  fi
  log_info "installing starship"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  curl --fail --location --silent --show-error --connect-timeout 15 --max-time 300 \
    -o "$tmp/starship.tar.gz" \
    https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-gnu.tar.gz ||
    curl --fail --location --silent --show-error --connect-timeout 15 --max-time 300 \
      -o "$tmp/starship.tar.gz" \
      https://github.com/starship/starship/releases/latest/download/starship-aarch64-unknown-linux-gnu.tar.gz ||
    {
      rm -rf "$tmp"
      return 1
    }
  tar -xzf "$tmp/starship.tar.gz" -C "$tmp"
  install -m 0755 "$tmp/starship" /usr/local/bin/starship
  rm -rf "$tmp"
}

_install_yq()
{
  if command -v yq >/dev/null 2>&1; then
    return 0
  fi
  log_info "installing yq"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  local tmp arch
  tmp="$(mktemp -d)"
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
  esac
  curl --fail --location --silent --show-error --connect-timeout 15 --max-time 300 \
    -o "$tmp/yq" "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${arch}"
  install -m 0755 "$tmp/yq" /usr/local/bin/yq
  rm -rf "$tmp"
}

_write_starship_config()
{
  local home="$1"
  ensure_directory "$home/.config" 0755
  ensure_file "$home/.config/starship.toml" \
    $'add_newline = true
command_timeout = 1000

[character]
success_symbol = "[➜](bold green)"
error_symbol = "[✗](bold red)"

[directory]
truncation_length = 4
truncation_symbol = "…/"

[git_branch]
symbol = " "

[git_status]
ahead = "⇡${count}"
diverged = "⇕⇡${ahead_count}⇣${behind_count}"
behind = "⇣${count}"
'
}

_write_zshrc()
{
  local home="$1"
  ensure_block "$home/.zshrc" "bootstrapx" \
    $'# zsh managed by BootstrapX — changes inside this block will be preserved.
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"

# fzf
if [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
  source /usr/share/fzf/key-bindings.zsh
  source /usr/share/fzf/completion.zsh
fi

# zoxide
if command -v zoxide >/dev/null; then
  eval "$(zoxide init zsh)"
fi

# direnv
if command -v direnv >/dev/null; then
  eval "$(direnv hook zsh)"
fi

# starship prompt
if command -v starship >/dev/null; then
  eval "$(starship init zsh)"
fi

# bat as manpager
export MANPAGER="sh -c '\''col -bx | bat -l man -p --paging always'\''"
export BAT_THEME="ansi"

# history
HISTSIZE=100000
SAVEHIST=100000
setopt INC_APPEND_HISTORY_TIME EXTENDED_HISTORY HIST_IGNORE_DUPS
'
}

_write_bashrc()
{
  local home="$1"
  ensure_block "$home/.bashrc" "bootstrapx" \
    $'# bash additions managed by BootstrapX
eval "$(starship init bash 2>/dev/null)" || true
if command -v direnv >/dev/null; then
  eval "$(direnv hook bash)"
fi
if command -v zoxide >/dev/null; then
  eval "$(zoxide init bash)"
fi
'
}

mod_55_shell_install()
{
  local admin="${ADMIN_USER:-admin}"

  # apt packages
  ensure_packages "${SHELL_PACKAGES_APT[@]}"
  # Some tools need extra pkg names depending on distro
  for pkg in "${SHELL_PACKAGES_EXTRA[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q '^install ok installed$'; then
      ensure_packages "$pkg" || log_warn "could not install $pkg from apt; will fall back"
    fi
  done

  _install_starship
  _install_yq

  # Per-user config.
  if user_exists "$admin"; then
    local home
    home="$(getent passwd "$admin" | cut -d: -f6)"
    if bootstrap_config_bool ENABLE_STARSHIP; then
      _write_starship_config "$home"
    fi
    if bootstrap_config_bool ENABLE_ZSH; then
      _write_zshrc "$home"
      # Set zsh as the admin login shell only if explicitly enabled.
      if bootstrap_config_bool ENABLE_ZSH_DEFAULT; then
        if ((!BOOTSTRAP_DRY_RUN)); then
          chsh -s /usr/bin/zsh "$admin" 2>/dev/null || true
        fi
      fi
    fi
    _write_bashrc "$home"
  fi
}

mod_55_shell_validate()
{
  command -v zsh >/dev/null || {
    log_error "zsh missing"
    return 1
  }
  command -v starship >/dev/null || log_warn "starship missing"
  command -v btop >/dev/null || log_warn "btop missing"
  command -v fzf >/dev/null || log_warn "fzf missing"
  command -v zoxide >/dev/null || log_warn "zoxide missing"
  return 0
}

mod_55_shell_rollback()
{
  :
}
