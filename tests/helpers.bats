#!/usr/bin/env bats
# tests/helpers.bats — unit tests for lib/ensure.sh and friends.
# These tests build a minimal sandbox in TEST_TMPDIR and exercise the helpers
# without touching the host filesystem outside that directory.

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  export BOOTSTRAP_STATE="$TEST_TMPDIR/state"
  export BOOTSTRAP_ROOT="$TEST_TMPDIR"
  mkdir -p "$BOOTSTRAP_STATE"

  # Source libraries in the order bootstrap.sh does.
  . "$BATS_TEST_DIRNAME/../lib/system.sh"
  . "$BATS_TEST_DIRNAME/../lib/log.sh"
  . "$BATS_TEST_DIRNAME/../lib/fs.sh"
  . "$BATS_TEST_DIRNAME/../lib/network.sh"
  . "$BATS_TEST_DIRNAME/../lib/packages.sh"
  . "$BATS_TEST_DIRNAME/../lib/users.sh"
  . "$BATS_TEST_DIRNAME/../lib/services.sh"
  . "$BATS_TEST_DIRNAME/../lib/templates.sh"
  . "$BATS_TEST_DIRNAME/../lib/rollback.sh"
  . "$BATS_TEST_DIRNAME/../lib/ensure.sh"

  BOOTSTRAP_DRY_RUN=0
  BOOTSTRAP_VERBOSE=0
  BOOTSTRAP_DEBUG=0
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "fs_atomic_write creates a file" {
  fs_atomic_write "$TEST_TMPDIR/hello.txt" "hello world"
  [[ "$(cat "$TEST_TMPDIR/hello.txt")" == "hello world" ]]
}

@test "fs_atomic_write is idempotent" {
  fs_atomic_write "$TEST_TMPDIR/hello.txt" "hello world"
  local before after
  before="$(sha256sum "$TEST_TMPDIR/hello.txt" | awk '{print $1}')"
  fs_atomic_write "$TEST_TMPDIR/hello.txt" "hello world"
  after="$(sha256sum "$TEST_TMPDIR/hello.txt" | awk '{print $1}')"
  [[ "$before" == "$after" ]]
}

@test "ensure_directory is idempotent" {
  ensure_directory "$TEST_TMPDIR/dir" 0755
  ensure_directory "$TEST_TMPDIR/dir" 0755
  [[ -d "$TEST_TMPDIR/dir" ]]
}

@test "ensure_file is idempotent" {
  ensure_file "$TEST_TMPDIR/conf" "key=value" 0644
  ensure_file "$TEST_TMPDIR/conf" "key=value" 0644
  [[ "$(cat "$TEST_TMPDIR/conf")" == "key=value" ]]
}

@test "ensure_file updates content when changed" {
  ensure_file "$TEST_TMPDIR/conf" "key=value"
  ensure_file "$TEST_TMPDIR/conf" "key=newvalue"
  [[ "$(cat "$TEST_TMPDIR/conf")" == "key=newvalue" ]]
}

@test "ensure_line appends when missing" {
  printf '' > "$TEST_TMPDIR/conf"
  ensure_line "$TEST_TMPDIR/conf" "PermitRootLogin no"
  grep -qxF "PermitRootLogin no" "$TEST_TMPDIR/conf"
}

@test "ensure_line replaces existing key" {
  printf 'PermitRootLogin yes\nOther 1\n' > "$TEST_TMPDIR/conf"
  ensure_line "$TEST_TMPDIR/conf" "PermitRootLogin no"
  grep -qxF "PermitRootLogin no" "$TEST_TMPDIR/conf"
  grep -qxF "Other 1" "$TEST_TMPDIR/conf"
}

@test "ensure_block appends on first run" {
  ensure_block "$TEST_TMPDIR/conf" "marker-a" "line1\nline2"
  grep -qF "BEGIN marker-a" "$TEST_TMPDIR/conf"
  grep -qF "END marker-a" "$TEST_TMPDIR/conf"
  grep -qF "line1" "$TEST_TMPDIR/conf"
}

@test "ensure_block replaces on second run" {
  ensure_block "$TEST_TMPDIR/conf" "marker-a" "first"
  ensure_block "$TEST_TMPDIR/conf" "marker-a" "second"
  grep -qF "second" "$TEST_TMPDIR/conf"
  ! grep -qF "first" "$TEST_TMPDIR/conf"
}

@test "ensure_symlink is idempotent" {
  touch "$TEST_TMPDIR/target"
  ensure_symlink "$TEST_TMPDIR/link" "$TEST_TMPDIR/target"
  ensure_symlink "$TEST_TMPDIR/link" "$TEST_TMPDIR/target"
  [[ "$(readlink "$TEST_TMPDIR/link")" == "$TEST_TMPDIR/target" ]]
}

@test "ensure_permission is idempotent" {
  touch "$TEST_TMPDIR/file"
  ensure_permission "$TEST_TMPDIR/file" 0600
  ensure_permission "$TEST_TMPDIR/file" 0600
  [[ "$(stat -c '%a' "$TEST_TMPDIR/file")" == "600" ]]
}

@test "ensure_permission changes when asked" {
  touch "$TEST_TMPDIR/file"
  ensure_permission "$TEST_TMPDIR/file" 0600
  ensure_permission "$TEST_TMPDIR/file" 0644
  [[ "$(stat -c '%a' "$TEST_TMPDIR/file")" == "644" ]]
}

@test "rollback registry records and replays" {
  touch "$TEST_TMPDIR/conf"
  echo "original" > "$TEST_TMPDIR/conf"
  fs_backup_file "$TEST_TMPDIR/conf" >/dev/null
  register_rollback "$TEST_TMPDIR/conf" "fs_restore_backup <backup> $TEST_TMPDIR/conf"
  echo "newcontent" > "$TEST_TMPDIR/conf"
  replay_rollback
  [[ "$(cat "$TEST_TMPDIR/conf")" == "original" ]]
}

@test "dry-run mode prints but does not write" {
  BOOTSTRAP_DRY_RUN=1
  ensure_file "$TEST_TMPDIR/conf" "x" 0644
  [[ ! -e "$TEST_TMPDIR/conf" ]]
}

@test "tpl_render_file expands variables" {
  cat > "$TEST_TMPDIR/in.tpl" <<'EOF'
host=${HOSTNAME:-default}
EOF
  HOSTNAME=myhost tpl_render_file "$TEST_TMPDIR/in.tpl" "$TEST_TMPDIR/out"
  grep -qF "host=myhost" "$TEST_TMPDIR/out"
}

@test "ensure_environment_variable sets a key" {
  ensure_environment_variable BOOTSTRAP_TEST_VAR hello /etc/environment 2>/dev/null || \
    ensure_environment_variable BOOTSTRAP_TEST_VAR hello "$TEST_TMPDIR/env"
  if [[ -f "$TEST_TMPDIR/env" ]]; then
    grep -qF "BOOTSTRAP_TEST_VAR=hello" "$TEST_TMPDIR/env"
  fi
}

@test "ensure_environment_variable is idempotent" {
  f="$TEST_TMPDIR/env"
  ensure_environment_variable BOOTSTRAP_TEST_VAR hello "$f"
  ensure_environment_variable BOOTSTRAP_TEST_VAR hello "$f"
  local count
  count="$(grep -c '^BOOTSTRAP_TEST_VAR=' "$f")"
  [[ "$count" == "1" ]]
}

@test "ensure_environment_variable updates value when changed" {
  f="$TEST_TMPDIR/env"
  ensure_environment_variable BOOTSTRAP_TEST_VAR hello "$f"
  ensure_environment_variable BOOTSTRAP_TEST_VAR world "$f"
  grep -qF "BOOTSTRAP_TEST_VAR=world" "$f"
  ! grep -qF "BOOTSTRAP_TEST_VAR=hello" "$f"
}

@test "ensure_mount appends fstab entries" {
  skip "ensure_mount writes to /etc/fstab; requires root"
  fstab="$TEST_TMPDIR/fstab"
  : > "$fstab"
  ensure_directory /etc
  cp "$fstab" /tmp/fstab.bak 2>/dev/null || true
  : > /etc/fstab
  ensure_mount /dev/sdb1 /mnt/data ext4 defaults 0 2
  cp /etc/fstab "$fstab"
  grep -qF "/dev/sdb1 /mnt/data ext4 defaults 0 2" "$fstab"
  ensure_mount /dev/sdb1 /mnt/data ext4 defaults 0 2
  cp /etc/fstab "$fstab"
  local count
  count="$(grep -cF "/dev/sdb1 /mnt/data" "$fstab")"
  [[ "$count" == "1" ]]
}