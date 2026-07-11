#!/usr/bin/env bash
# modules/40-podman.sh — Stage 4: rootless Podman, buildah, skopeo, registries.
set -Eeuo pipefail

mod_40_podman_description() { echo "Podman rootless, buildah, skopeo, Quadlets, registries"; }
mod_40_podman_stage()       { echo "4"; }
mod_40_podman_dependencies(){ echo "30-security"; }

mod_40_podman_check() {
  command -v podman >/dev/null || return 1
  command -v buildah >/dev/null || return 1
  command -v skopeo >/dev/null || return 1
  return 0
}

mod_40_podman_install() {
  ensure_packages podman buildah skopeo uidmap fuse-overlayfs slirp4netns

  local admin="${ADMIN_USER:-admin}"

  # subuid + subgid so the admin user can map ranges for rootless containers.
  if ! grep -qE "^${admin}:" /etc/subuid 2>/dev/null; then
    log_info "configuring subuid/subgid for $admin"
    if (( ! BOOTSTRAP_DRY_RUN )); then
      fs_backup_file /etc/subuid >/dev/null || true
      printf '%s:100000:65536\n' "$admin" >> /etc/subuid
      register_rollback "/etc/subuid" "fs_restore_backup <backup> /etc/subuid"
      fs_backup_file /etc/subgid >/dev/null || true
      printf '%s:100000:65536\n' "$admin" >> /etc/subgid
      register_rollback "/etc/subgid" "fs_restore_backup <backup> /etc/subgid"
    fi
  fi

  # Enable lingering so user services (Quadlets) start without an open session.
  if id "$admin" >/dev/null 2>&1; then
    log_info "enabling linger for $admin"
    if (( ! BOOTSTRAP_DRY_RUN )); then
      loginctl enable-linger "$admin" 2>/dev/null || true
    fi
  fi

  # registries.conf: search the configured registries.
  local registries="${PODMAN_REGISTRIES:-docker.io quay.io ghcr.io}"
  ensure_file /etc/containers/registries.conf \
$'unqualified-search-registries = ["'"${registries}"$'"]
short-name-mode = "permissive"
'

  # storage.conf: enable fuse-overlayfs for unprivileged users.
  ensure_file /etc/containers/storage.conf \
$'[storage]
driver = "overlay"
runroot = "/run/containers/storage"
graphroot = "'"${PODMAN_STORAGE:-/var/lib/containers/storage}"$'"

[storage.options]
mount_program = "/usr/bin/fuse-overlayfs"
mountopt = "nodev,metacopy=on"
'

  # Quadlet example installed under documentation (real module author copies
  # to ~/.config/containers/systemd/ to activate). See files/quadlets/.
  ensure_directory /usr/share/bootstrapx/quadlets/examples 0755 root:root
  if [[ -f "$BOOTSTRAP_FILES/quadlets/hello.container" ]]; then
    fs_copy "$BOOTSTRAP_FILES/quadlets/hello.container" \
            /usr/share/bootstrapx/quadlets/examples/hello.container
  fi
}

mod_40_podman_validate() {
  command -v podman >/dev/null || { log_error "podman not installed"; return 1; }
  command -v buildah >/dev/null || { log_error "buildah not installed"; return 1; }
  command -v skopeo >/dev/null || { log_error "skopeo not installed"; return 1; }
  local admin="${ADMIN_USER:-admin}"
  if id "$admin" >/dev/null 2>&1; then
    su - "$admin" -s /bin/bash -c 'podman info >/dev/null 2>&1' \
      || log_warn "rootless podman info failed for $admin (may need re-login for subuid/subgid)"
  fi
  return 0
}

mod_40_podman_rollback() {
  # Uninstall pods but keep registries.conf as a config; rely on package manager purge.
  :
}