#!/usr/bin/env bash
# lib/fs.sh — filesystem primitives: atomic writes, backups, permissions.
# Deps: log.
set -Eeuo pipefail

_fs_path_owner() {
  # owner_user, owner_group, owner_mode
  stat -c '%U %G %a' -- "$1"
}

fs_dir_exists()  { [[ -d "$1" ]]; }
fs_file_exists() { [[ -f "$1" ]]; }
fs_link_exists() { [[ -L "$1" ]]; }
fs_readable()    { [[ -r "$1" ]]; }

fs_mkdir_p() {
  local dir="$1"
  if fs_dir_exists "$dir"; then
    return 0
  fi
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would mkdir -p $dir"
    return 0
  fi
  mkdir -p -- "$dir"
}

fs_atomic_write() {
  # Writes $1 with content $2, mode 0644, atomically (write-then-rename).
  local path="$1" content="$2"
  local dir tmp
  dir="$(dirname -- "$path")"
  fs_mkdir_p "$dir"
  tmp="$(mktemp "$dir/.bootstrapx.XXXXXX")"
  printf '%s' "$content" > "$tmp"
  chmod 0644 "$tmp"
  mv -f -- "$tmp" "$path"
}

fs_copy() {
  local src="$1" dst="$2"
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would cp $src $dst"
    return 0
  fi
  fs_mkdir_p "$(dirname -- "$dst")"
  cp -f -- "$src" "$dst"
}

fs_chmod() {
  local mode="$1" path="$2"
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would chmod $mode $path"
    return 0
  fi
  chmod "$mode" -- "$path"
}

fs_chown() {
  local owner="$1" path="$2"
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would chown $owner $path"
    return 0
  fi
  bootstrap_chown_if_root -- "$owner" "$path"
}

# bootstrap_chown_if_root OWNER PATH... — chown only when running as root.
# Non-root callers (e.g. tests) silently skip; warns once.
bootstrap_chown_if_root() {
  if ! bootstrap_system_is_root; then
    return 0
  fi
  chown "$@"
}

# backup_file PATH → echoes backup path.
# Backups live under $BOOTSTRAP_STATE/backups/<sha1-of-path>/<basename>.<timestamp>
fs_backup_file() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    return 1
  fi
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would back up $path"
    return 0
  fi
  local bucket ts backup
  bucket="$(printf '%s' "$path" | sha1sum | awk '{print $1}')"
  ts="$(date -u +'%Y%m%dT%H%M%SZ')"
  local dir="$BOOTSTRAP_STATE/backups/$bucket"
  fs_mkdir_p "$dir"
  backup="$dir/$(basename -- "$path").$ts"
  cp -a -- "$path" "$backup"
  printf '%s\n' "$backup"
}

fs_restore_backup() {
  local backup="$1" target="$2"
  if [[ ! -e "$backup" ]]; then
    log_warn "no backup to restore: $backup"
    return 1
  fi
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would restore $backup -> $target"
    return 0
  fi
  fs_mkdir_p "$(dirname -- "$target")"
  cp -a -- "$backup" "$target"
}

# sha256 of a file or stdin. Echoes hex.
fs_sha256_file() {
  sha256sum -- "$1" | awk '{print $1}'
}