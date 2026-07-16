#!/usr/bin/env bash
# lib/users.sh — user/group helpers used by ensure_user/ensure_group and the users module.
# Deps: log, fs.
set -Eeuo pipefail

# Returns the smallest free UID >= 1000 excluding nobody and sshd reserved.
user_next_uid()
{
  local uid
  uid="$(awk -F: '($3>=1000) && ($3<60000) {print $3}' /etc/passwd | sort -n | tail -1)"
  uid="${uid:-999}"
  printf '%d\n' $((uid + 1))
}

user_exists()
{
  id -u -- "$1" >/dev/null 2>&1
}
group_exists()
{
  getent group "$1" >/dev/null
}

user_create()
{
  local name="$1" home="${2:-/home/$1}" shell="${3:-/bin/bash}"
  if user_exists "$name"; then
    return 0
  fi
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would useradd --create-home --home $home --shell $shell $name"
    return 0
  fi
  local -a args=(--create-home --home-dir "$home" --shell "$shell")
  if group_exists "$name"; then
    args+=(--gid "$name")
  fi
  useradd "${args[@]}" "$name"
}

user_delete()
{
  local name="$1"
  user_exists "$name" || return 0
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would userdel -r $name"
    return 0
  fi
  userdel -r "$name" 2>/dev/null || true
}

group_create()
{
  local name="$1"
  group_exists "$name" && return 0
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would groupadd $name"
    return 0
  fi
  groupadd "$name"
}

user_add_to_group()
{
  local user="$1" group="$2"
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would usermod -aG $group $user"
    return 0
  fi
  usermod -aG "$group" "$user"
}

# Writes /etc/sudoers.d/<user> with passwordless sudo. Validates with visudo -c.
sudoers_install_snippet()
{
  local user="$1"
  local content="$2"
  local path="/etc/sudoers.d/${user}"
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would write $path"
    return 0
  fi
  fs_backup_file "$path" >/dev/null || true
  fs_atomic_write "$path" "$content"
  chmod 0440 -- "$path"
  if ! visudo -c -f "$path" >/dev/null; then
    log_error "sudoers snippet invalid: $path"
    fs_restore_backup "$(ls -1t "$BOOTSTRAP_STATE/backups/"*"/${user}".* 2>/dev/null | head -1)" "$path" 2>/dev/null || rm -f -- "$path"
    return 1
  fi
  register_rollback "$path" "fs_restore_backup <backup> $path"
}

sudoers_remove_snippet()
{
  local user="$1"
  local path="/etc/sudoers.d/${user}"
  if [[ ! -e "$path" ]]; then
    return 0
  fi
  rm -f -- "$path"
}

# install_authorized_keys USER KEY_STRING...
# Writes one canonical key per line, mode 0600.
ssh_install_authorized_keys()
{
  local user="$1"
  shift
  local home key_file
  home="$(getent passwd "$user" | cut -d: -f6)"
  if [[ -z "$home" ]]; then
    log_error "no home for user: $user"
    return 1
  fi
  key_file="$home/.ssh/authorized_keys"
  if ((BOOTSTRAP_DRY_RUN)); then
    log_info "would write $key_file"
    return 0
  fi
  fs_mkdir_p "$home/.ssh"
  chmod 0700 "$home/.ssh"
  local tmp
  tmp="$(mktemp)"
  local k
  for k in "$@"; do
    [[ -z "$k" || "$k" =~ ^[[:space:]]*# ]] && continue
    printf '%s\n' "$k" >>"$tmp"
  done
  if [[ -s "$tmp" ]]; then
    fs_backup_file "$key_file" >/dev/null || true
    cp -f -- "$tmp" "$key_file"
    chmod 0600 "$key_file"
    chown -R "$user:$user" "$home/.ssh"
    register_rollback "$key_file" "fs_restore_backup <backup> $key_file"
  fi
  rm -f -- "$tmp"
}

ssh_user_keycount()
{
  local user="$1"
  local home key_file
  home="$(getent passwd "$user" | cut -d: -f6)"
  local key_file="$home/.ssh/authorized_keys"
  [[ -r "$key_file" ]] || {
    echo 0
    return
  }
  grep -cvE '^[[:space:]]*(#|$)' "$key_file"
}
