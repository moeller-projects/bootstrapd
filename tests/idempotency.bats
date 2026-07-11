#!/usr/bin/env bats
# tests/idempotency.bats — proves that running helpers twice yields the same
# filesystem and that "second run == noop" semantics hold.

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  export BOOTSTRAP_ROOT="$TEST_TMPDIR"
  export BOOTSTRAP_STATE="$TEST_TMPDIR/state"
  mkdir -p "$BOOTSTRAP_STATE"
  export BOOTSTRAP_LIB="$BATS_TEST_DIRNAME/../lib"

  . "$BOOTSTRAP_LIB/system.sh"
  . "$BOOTSTRAP_LIB/log.sh"
  . "$BOOTSTRAP_LIB/fs.sh"
  . "$BOOTSTRAP_LIB/network.sh"
  . "$BOOTSTRAP_LIB/packages.sh"
  . "$BOOTSTRAP_LIB/users.sh"
  . "$BOOTSTRAP_LIB/services.sh"
  . "$BOOTSTRAP_LIB/templates.sh"
  . "$BOOTSTRAP_LIB/rollback.sh"
  . "$BOOTSTRAP_LIB/ensure.sh"

  BOOTSTRAP_DRY_RUN=0
  BOOTSTRAP_VERBOSE=0
  BOOTSTRAP_DEBUG=0
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

snapshot_tree() {
  ( cd "$TEST_TMPDIR" && find . -type f -not -path './state/backups/*' | sort | xargs -I{} sha256sum "{}" 2>/dev/null ) || true
}

@test "ensure_file: 100 runs, one canonical content, no churn" {
  ensure_file "$TEST_TMPDIR/c" "stable" 0644
  local first
  first="$(sha256sum "$TEST_TMPDIR/c" | awk '{print $1}')"
  local i
  for ((i=0; i<100; i++)); do
    ensure_file "$TEST_TMPDIR/c" "stable" 0644
  done
  local last
  last="$(sha256sum "$TEST_TMPDIR/c" | awk '{print $1}')"
  [[ "$first" == "$last" ]]
}

@test "ensure_block: first run appends, second run rewrites same content" {
  ensure_block "$TEST_TMPDIR/c" "block-a" "x=1"
  local first
  first="$(sha256sum "$TEST_TMPDIR/c" | awk '{print $1}')"
  ensure_block "$TEST_TMPDIR/c" "block-a" "x=1"
  local second
  second="$(sha256sum "$TEST_TMPDIR/c" | awk '{print $1}')"
  [[ "$first" == "$second" ]]
}

@test "ensure_line: replace-then-stable produces stable output" {
  printf 'PermitRootLogin yes\n' > "$TEST_TMPDIR/c"
  ensure_line "$TEST_TMPDIR/c" "PermitRootLogin no"
  ensure_line "$TEST_TMPDIR/c" "PermitRootLogin no"
  ensure_line "$TEST_TMPDIR/c" "PermitRootLogin no"
  local count
  count="$(grep -c '^PermitRootLogin' "$TEST_TMPDIR/c")"
  [[ "$count" == "1" ]]
  grep -qF 'PermitRootLogin no' "$TEST_TMPDIR/c"
}

@test "ensure_directory+ensure_permission: 10 runs in a row, state stable" {
  ensure_directory "$TEST_TMPDIR/d" 0755
  ensure_permission "$TEST_TMPDIR/d" 0755
  local first
  first="$(stat -c '%a' "$TEST_TMPDIR/d")"
  local i
  for ((i=0; i<10; i++)); do
    ensure_directory "$TEST_TMPDIR/d" 0755
    ensure_permission "$TEST_TMPDIR/d" 0755
  done
  [[ "$first" == "$(stat -c '%a' "$TEST_TMPDIR/d")" ]]
}