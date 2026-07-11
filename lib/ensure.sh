#!/usr/bin/env bash
# lib/ensure.sh — every ensure_* idempotency helper.
# Deps: log, fs, packages, users, services, templates, rollback.
set -Eeuo pipefail

# Generic guards reused by every helper.

ensure_dryrun_skip()
{
  ((BOOTSTRAP_DRY_RUN))
}

# ---------- packages ----------

ensure_package()
{
  local name="$1"
  if pkg_installed "$name"; then
    log_debug "package already installed: $name"
    return 0
  fi
  log_info "installing package: $name"
  pkg_install "$name"
}

ensure_packages()
{
  local missing=()
  while (($#)); do
    pkg_installed "$1" || missing+=("$1")
    shift
  done
  if ((${#missing[@]} == 0)); then
    log_debug "all packages already installed"
    return 0
  fi
  log_info "installing packages: ${missing[*]}"
  pkg_install_many "${missing[@]}"
}

ensure_repo()
{
  local uri="$1" name="$2" signed_by="${3:-}"
  local path="/etc/apt/sources.list.d/${name}.sources"
  if fs_file_exists "$path" && grep -q "$uri" "$path"; then
    log_debug "repo already configured: $name"
    return 0
  fi
  log_info "adding apt repo: $name ($uri)"
  pkg_repo_add "$uri" "$name" "$signed_by"
}

ensure_gpg_key()
{
  local url="$1" dest="$2"
  if fs_file_exists "$dest"; then
    log_debug "GPG key already present: $dest"
    return 0
  fi
  log_info "fetching GPG key: $url"
  pkg_gpg_key_install "$url" "$dest"
}

# ---------- users and groups ----------

ensure_user()
{
  local name="$1" home="${2:-/home/$1}" shell="${3:-/bin/bash}"
  if user_exists "$name"; then
    log_debug "user exists: $name"
    return 0
  fi
  log_info "creating user: $name"
  user_create "$name" "$home" "$shell"
}

ensure_group()
{
  local name="$1"
  if group_exists "$name"; then
    log_debug "group exists: $name"
    return 0
  fi
  log_info "creating group: $name"
  group_create "$name"
}

ensure_user_in_group()
{
  local user="$1" group="$2"
  if id -nG -- "$user" 2>/dev/null | tr ' ' '\n' | grep -qx "$group"; then
    log_debug "$user already in group $group"
    return 0
  fi
  log_info "adding $user to group $group"
  user_add_to_group "$user" "$group"
}

# ---------- filesystem ----------

ensure_directory()
{
  local dir="$1" mode="${2:-0755}" owner="${3:-root:root}"
  if fs_dir_exists "$dir"; then
    if ((BOOTSTRAP_VERBOSE)); then
      local cur
      cur="$(_fs_path_owner "$dir")"
      log_debug "directory exists: $dir (owner=$cur)"
    fi
    return 0
  fi
  log_info "creating directory: $dir (mode $mode, owner $owner)"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  mkdir -p -- "$dir"
  chmod "$mode" -- "$dir"
  bootstrap_chown_if_root -- "$owner" "$dir"
}

ensure_file()
{
  local path="$1" content="$2" mode="${3:-0644}" owner="${4:-root:root}"
  if fs_file_exists "$path"; then
    if [[ "$(cat -- "$path")" == "$content" ]]; then
      log_debug "file unchanged: $path"
      return 0
    fi
    log_info "updating file: $path"
  else
    log_info "writing file: $path"
  fi
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  fs_backup_file "$path" >/dev/null || true
  local dir tmp
  dir="$(dirname -- "$path")"
  fs_mkdir_p "$dir"
  tmp="$(mktemp "$dir/.bootstrapx.XXXXXX")"
  printf '%s' "$content" >"$tmp"
  chmod "$mode" "$tmp"
  bootstrap_chown_if_root -- "$owner" "$tmp"
  mv -f -- "$tmp" "$path"
  register_rollback "$path" "fs_restore_backup <backup> $path"
}

ensure_template()
{
  local src="$1" dest="$2" mode="${3:-0644}" owner="${4:-root:root}"
  local rendered
  rendered="$(envsubst <"$src")"
  if fs_file_exists "$dest" && [[ "$(cat -- "$dest")" == "$rendered" ]]; then
    log_debug "template-rendered file unchanged: $dest"
    return 0
  fi
  log_info "rendering template: $src -> $dest"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  tpl_render_file "$src" "$dest" "$mode"
  chown -- "$owner" "$dest"
}

# ensure_line FILE LINE — replaces the matching line if any, appends otherwise.
# The match is exact-string on the leading key (first whitespace-delimited token).
ensure_line()
{
  local path="$1" line="$2"
  if fs_file_exists "$path" && grep -qxF "$line" -- "$path"; then
    log_debug "line already present in $path"
    return 0
  fi
  log_info "patching line in $path"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  fs_backup_file "$path" >/dev/null || true
  fs_mkdir_p "$(dirname -- "$path")"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "$path" ]]; then
    # Drop any existing line that starts with the same leading key (key = first token).
    local key
    key="${line%% *}"
    awk -v key="$key" 'BEGIN{OFS=""} !($1==key)' "$path" >"$tmp" || true
  else
    : >"$tmp"
  fi
  printf '%s\n' "$line" >>"$tmp"
  mv -f -- "$tmp" "$path"
  register_rollback "$path" "fs_restore_backup <backup> $path"
}

# ensure_block FILE MARKER TEXT — replaces text between # BEGIN MARKER / # END MARKER
# in place. Idempotent: a second call with identical content produces an identical file.
ensure_block()
{
  local path="$1" marker="$2" content="$3"
  local begin="# BEGIN ${marker}"
  local end="# END ${marker}"
  local block="${begin}
${content}
${end}"
  if fs_file_exists "$path" &&
    grep -qF "$begin" -- "$path" &&
    grep -qF "$end" -- "$path"; then
    if ((BOOTSTRAP_DRY_RUN)); then
      log_info "would refresh block $marker in $path"
      return 0
    fi
    log_info "refreshing block $marker in $path"
    fs_backup_file "$path" >/dev/null || true
    local tmp
    tmp="$(mktemp)"
    awk -v b="$begin" -v e="$end" -v nb="$block" '
      $0==b {print nb; skip=1; next}
      $0==e {skip=0; next}
      skip {next}
      {print}
    ' "$path" >"$tmp"
    mv -f -- "$tmp" "$path"
    register_rollback "$path" "fs_restore_backup <backup> $path"
    return 0
  fi
  log_info "appending block $marker to $path"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  fs_backup_file "$path" >/dev/null || true
  printf '\n%s\n' "$block" >>"$path"
  register_rollback "$path" "fs_restore_backup <backup> $path"
}

ensure_symlink()
{
  local link="$1" target="$2"
  if fs_link_exists "$link" && [[ "$(readlink -- "$link")" == "$target" ]]; then
    log_debug "symlink already correct: $link -> $target"
    return 0
  fi
  log_info "creating symlink: $link -> $target"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  fs_mkdir_p "$(dirname -- "$link")"
  [[ -e "$link" || -L "$link" ]] && rm -f -- "$link"
  ln -s -- "$target" "$link"
}

ensure_permission()
{
  local path="$1" mode="$2" owner="${3:-}"
  local cur_mode cur_owner
  cur_mode="$(stat -c '%a' -- "$path" 2>/dev/null || echo "")"
  cur_owner="$(stat -c '%U:%G' -- "$path" 2>/dev/null || echo "")"
  if [[ "$cur_mode" == "$mode" && (-z "$owner" || "$cur_owner" == "$owner") ]]; then
    log_debug "permission already correct: $path"
    return 0
  fi
  log_info "fixing permission on $path ($cur_mode -> $mode${owner:+,$cur_owner -> $owner})"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  chmod "$mode" -- "$path"
  if [[ -n "$owner" ]]; then
    bootstrap_chown_if_root -- "$owner" "$path"
  fi
  return 0
}

# ---------- services ----------

ensure_service_enabled()
{
  local name="$1"
  if svc_enabled "$name"; then
    log_debug "service already enabled: $name"
    return 0
  fi
  log_info "enabling service: $name"
  svc_enable "$name"
}

ensure_service_disabled()
{
  local name="$1"
  if ! svc_enabled "$name" && ! svc_active "$name"; then
    log_debug "service already disabled: $name"
    return 0
  fi
  log_info "disabling service: $name"
  svc_disable "$name"
}

ensure_service_running()
{
  local name="$1"
  if svc_active "$name"; then
    log_debug "service already running: $name"
    return 0
  fi
  log_info "starting service: $name"
  svc_start "$name"
}

# ensure_service_sshd_reload  — special case for sshd: validate then reload.
ensure_service_sshd_reload()
{
  log_info "validating and reloading sshd"
  sshd_reload_safely
}

# ---------- system ----------

ensure_sysctl()
{
  local key="$1" value="$2"
  local cur
  cur="$(sysctl -n "$key" 2>/dev/null || echo "")"
  if [[ "$cur" == "$value" ]]; then
    log_debug "sysctl already correct: $key = $value"
    return 0
  fi
  log_info "setting sysctl $key = $value"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  local conf="/etc/sysctl.d/99-bootstrapx.conf"
  ensure_line "$conf" "$key = $value"
  sysctl -w "$key=$value" >/dev/null
}

ensure_hostname()
{
  local name="$1"
  local cur
  cur="$(hostnamectl --static status 2>/dev/null || hostname)"
  if [[ "$cur" == "$name" ]]; then
    log_debug "hostname already $name"
    return 0
  fi
  log_info "setting hostname: $name"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  hostnamectl set-hostname "$name"
}

ensure_timezone()
{
  local tz="$1"
  local cur="/etc/localtime"
  local want="/usr/share/zoneinfo/$tz"
  if [[ -e "$cur" ]] && cmp -s "$cur" "$want"; then
    log_debug "timezone already $tz"
    return 0
  fi
  log_info "setting timezone: $tz"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  ln -sf -- "$want" "$cur"
  dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1 || true
}

ensure_locale()
{
  local loc="$1"
  if locale -a 2>/dev/null | grep -qx "$loc"; then
    log_debug "locale already generated: $loc"
    return 0
  fi
  log_info "generating locale: $loc"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  ensure_line /etc/locale.gen "$loc UTF-8"
  locale-gen >/dev/null
  update-locale LANG="$loc" >/dev/null
}

# ---------- scheduled jobs ----------

ensure_cron()
{
  local spec="$1" user="${2:-root}"
  local marker="# bootstrapx-managed"
  local line="$spec $marker"
  if crontab -u "$user" -l 2>/dev/null | grep -qF "$marker"; then
    log_debug "cron already present for $user"
    return 0
  fi
  log_info "installing cron for $user: $spec"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  crontab -u "$user" -l 2>/dev/null >"$tmp" || true
  printf '%s\n' "$line" >>"$tmp"
  crontab -u "$user" -- "$tmp"
  rm -f -- "$tmp"
}

ensure_timer()
{
  # Best-effort: defers to the calling module to write the unit file, then enables+starts.
  local unit="$1"
  log_info "ensuring timer: $unit"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  systemctl enable --now -- "$unit"
}

# ---------- environment ----------

ensure_environment_variable()
{
  local name="$1" value="$2" scope="${3:-/etc/environment}"
  if [[ -f "$scope" ]] && grep -qE "^${name}=" "$scope"; then
    local cur
    cur="$(awk -F= -v n="$name" '$1==n {sub(/^[^=]+=/, ""); print}' "$scope")"
    if [[ "$cur" == "$value" ]]; then
      log_debug "env $name already set"
      return 0
    fi
    log_info "updating env $name"
    fs_backup_file "$scope" >/dev/null || true
    awk -v n="$name" -v v="$value" '
      BEGIN{FS="="; OFS="="}
      $1==n {print n, v; next}
      {print}
    ' "$scope" >"${scope}.tmp"
    mv -f -- "${scope}.tmp" "$scope"
    register_rollback "$scope" "fs_restore_backup <backup> $scope"
  else
    log_info "adding env $name"
    fs_backup_file "$scope" >/dev/null || true
    printf '\n%s=%s\n' "$name" "$value" >>"$scope"
    register_rollback "$scope" "fs_restore_backup <backup> $scope"
  fi
}

# ensure_mount SOURCE TARGET FSTYPE OPTIONS — appends to /etc/fstab if missing.
# SOURCE, TARGET, FSTYPE, OPTIONS are fstab fields. dump/pass default to 0 2.
ensure_mount()
{
  local src="$1" target="$2" fstype="$3" opts="${4:-defaults}" dump="${5:-0}" pass="${6:-2}"
  local fstab="/etc/fstab"
  local entry="${src} ${target} ${fstype} ${opts} ${dump} ${pass}"
  if [[ -f "$fstab" ]] && grep -qF "$src $target" "$fstab"; then
    log_debug "fstab entry already present: $src -> $target"
    return 0
  fi
  log_info "adding fstab mount: $entry"
  if ((BOOTSTRAP_DRY_RUN)); then
    return 0
  fi
  fs_backup_file "$fstab" >/dev/null || true
  printf '%s\n' "$entry" >>"$fstab"
  register_rollback "$fstab" "fs_restore_backup <backup> $fstab"
  fs_mkdir_p "$target"
}
