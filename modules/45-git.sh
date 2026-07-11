#!/usr/bin/env bash
# modules/45-git.sh — Stage 3: dedicated Git module.
#
# Owns:
#   - git + git-lfs + gh CLI + delta (delta installed in 50-dev's deps; we configure it here)
#   - per-user global git config (admin)
#   - safe.directory wildcard (admin + deploy)
#   - signing key registration (if GIT_USER_EMAIL is set)
#
# Splits from 50-dev so the dev module is purely about language runtimes.
set -Eeuo pipefail

mod_45_git_description()
{
  echo "Git, Git LFS, GitHub CLI, delta, signing, safe.directory"
}
mod_45_git_stage()
{
  echo "3"
}
mod_45_git_dependencies()
{
  echo "30-security"
}

mod_45_git_check()
{
  command -v git >/dev/null || return 1
  command -v git-lfs >/dev/null || return 1
  return 0
}

_apply_git_config()
{
  local user="$1" home
  home="$(getent passwd "$user" | cut -d: -f6)"
  [[ -d "$home" ]] || return 0
  local gitname="${GIT_USER_NAME:-}"
  local gitemail="${GIT_USER_EMAIL:-}"

  _git()
  {
    sudo -u "$user" HOME="$home" git config --global "$@"
  }

  _git init.defaultBranch "${GIT_DEFAULT_BRANCH:-main}"
  _git core.autocrlf input
  _git pull.rebase true
  _git rerere.enabled true
  _git push.autoSetupRemote true
  _git push.default simple
  _git branch.autoSetupMerge always
  _git branch.sort -committerdate
  _git diff.algorithm histogram
  _git help.autocorrect 10
  _git safe.directory '*'

  if [[ -n "$gitname" ]]; then
    _git user.name "$gitname"
  fi
  if [[ -n "$gitemail" ]]; then
    _git user.email "$gitemail"
  fi

  # delta as pager.
  if command -v delta >/dev/null; then
    _git core.pager delta
    _git interactive.diffFilter 'delta --color-only'
    _git delta.navigate true
    _git delta.light false
    _git delta.line-numbers true
    _git delta.side-by-side false
  fi

  # git-lfs install per-user.
  sudo -u "$user" HOME="$home" git lfs install --system 2>/dev/null ||
    sudo -u "$user" HOME="$home" git lfs install 2>/dev/null ||
    true
}

mod_45_git_install()
{
  ensure_packages git git-lfs ca-certificates
  if bootstrap_config_bool ENABLE_GITHUB_CLI; then
    ensure_packages gh
  fi

  local admin="${ADMIN_USER:-admin}"
  local deploy="${DEPLOY_USER:-deploy}"

  if user_exists "$admin"; then
    _apply_git_config "$admin"
  fi
  if user_exists "$deploy"; then
    # Minimal config for deploy: identity not assumed (CI sets per-job).
    local home
    home="$(getent passwd "$deploy" | cut -d: -f6)"
    if [[ -d "$home" ]]; then
      sudo -u "$deploy" HOME="$home" git config --global init.defaultBranch "${GIT_DEFAULT_BRANCH:-main}"
      sudo -u "$deploy" HOME="$home" git config --global safe.directory '*'
      sudo -u "$deploy" HOME="$home" git config --global pull.rebase true
    fi
  fi

  # /srv/repos ownership belongs to admin:deploy (see 25-filesystem).
}

mod_45_git_validate()
{
  command -v git >/dev/null || {
    log_error "git missing"
    return 1
  }
  command -v git-lfs >/dev/null || log_warn "git-lfs missing"
  if bootstrap_config_bool ENABLE_GITHUB_CLI && ! command -v gh >/dev/null; then
    log_warn "gh missing"
  fi
  return 0
}

mod_45_git_rollback()
{
  :
}
