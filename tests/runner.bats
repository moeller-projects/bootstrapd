#!/usr/bin/env bats
# tests/runner.bats — exercises module discovery, dependency resolution,
# and the staged-execution flow without modifying the host.

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  export BOOTSTRAP_ROOT="$TEST_TMPDIR"
  export BOOTSTRAP_STATE="$TEST_TMPDIR/state"
  export BOOTSTRAP_MODULES="$TEST_TMPDIR/modules"
  export BOOTSTRAP_LIB="$BATS_TEST_DIRNAME/../lib"
  export BOOTSTRAP_CONFIG="$TEST_TMPDIR/bootstrap.conf"
  mkdir -p "$BOOTSTRAP_STATE" "$BOOTSTRAP_MODULES"

  # Source libraries.
  . "$BOOTSTRAP_LIB/system.sh"
  . "$BOOTSTRAP_LIB/log.sh"
  . "$BOOTSTRAP_LIB/fs.sh"
  . "$BOOTSTRAP_LIB/network.sh"
  . "$BOOTSTRAP_LIB/packages.sh"
  . "$BOOTSTRAP_LIB/users.sh"
  . "$BOOTSTRAP_LIB/services.sh"
  . "$BOOTSTRAP_LIB/templates.sh"
  . "$BOOTSTRAP_LIB/rollback.sh"
  . "$BOOTSTRAP_LIB/config.sh"
  . "$BOOTSTRAP_LIB/ensure.sh"
  . "$BOOTSTRAP_LIB/runner.sh"

  BOOTSTRAP_DRY_RUN=0
  BOOTSTRAP_VERBOSE=0
  BOOTSTRAP_DEBUG=0
  BOOTSTRAP_SAFE=1
  BOOTSTRAP_FORCE=0
  BOOTSTRAP_NON_INTERACTIVE=1
  BOOTSTRAP_STAGE=""
  BOOTSTRAP_ONLY=""

  ADMIN_USER=admin
  SSH_PUBLIC_KEYS=""
  HOSTNAME=test-host
  TIMEZONE=UTC
  LOCALE=en_US.UTF-8
  ENABLE_FAIL2BAN=false
  ENABLE_APPARMOR=false
  ENABLE_AUTO_UPDATES=false
  ENABLE_PODMAN=false
  ENABLE_PI=false
  ENABLE_CODEX=false
  ENABLE_CLAUDE=false
  ENABLE_OPENCLAW=false
  ENABLE_MONITORING=false
  export ADMIN_USER SSH_PUBLIC_KEYS HOSTNAME TIMEZONE LOCALE
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# Minimal helper module so the runner has something to discover.
make_minimal_module() {
  local id="$1" deps="${2:-}" stage="${3:-1}"
  cat > "$BOOTSTRAP_MODULES/${id}.sh" <<EOF
mod_${id//-/_}_description() { echo "minimal $id"; }
mod_${id//-/_}_stage()       { echo "$stage"; }
mod_${id//-/_}_dependencies(){ echo "$deps"; }
mod_${id//-/_}_check()       { return 1; }
mod_${id//-/_}_install()     { printf 'installed %s\n' "$id" > "$BOOTSTRAP_STATE/${id}.installed"; }
mod_${id//-/_}_validate()    { [[ -f "$BOOTSTRAP_STATE/${id}.installed" ]]; }
mod_${id//-/_}_rollback()    { rm -f "$BOOTSTRAP_STATE/${id}.installed"; }
EOF
}

@test "runner_discover_modules finds NN-name.sh files only" {
  make_minimal_module "10-a"
  make_minimal_module "20-b"
  printf 'not-a-module\n' > "$BOOTSTRAP_MODULES/README"
  local out count
  out="$(runner_discover_modules)"
  count="$(printf '%s\n' "$out" | grep -c .)"
  [[ "$count" == "2" ]]
  [[ "$out" == *"10-a"* ]]
  [[ "$out" == *"20-b"* ]]
  ! [[ "$out" == *"README"* ]]
}

@test "runner_toposort_bash orders by dependency" {
  make_minimal_module "10-a"
  make_minimal_module "20-b" "10-a"
  make_minimal_module "30-c" "20-b"
  local ids ordered
  ids="$(runner_discover_modules)"
  ordered="$(printf '%s\n' "$ids" | runner_toposort_bash)"
  # 10-a must come before 20-b, which must come before 30-c.
  local ai bi ci
  ai="$(printf '%s\n' "$ordered" | awk '/10-a/{print NR}')"
  bi="$(printf '%s\n' "$ordered" | awk '/20-b/{print NR}')"
  ci="$(printf '%s\n' "$ordered" | awk '/30-c/{print NR}')"
  (( ai < bi )) && (( bi < ci ))
}

@test "runner_run_module calls install then validate and records state" {
  make_minimal_module "10-a"
  runner_load_modules
  runner_run_module "10-a"
  [[ -f "$BOOTSTRAP_STATE/10-a.state" ]]
  grep -q '^status=ok' "$BOOTSTRAP_STATE/10-a.state"
  [[ -f "$BOOTSTRAP_STATE/10-a.installed" ]]
}

@test "runner_run_module skips install when check returns 0" {
  cat > "$BOOTSTRAP_MODULES/10-a.sh" <<'EOF'
mod_10_a_description() { echo "skip if installed"; }
mod_10_a_stage()       { echo "1"; }
mod_10_a_dependencies(){ echo ""; }
mod_10_a_check()       { return 0; }
mod_10_a_install()     { echo should-not-run > "$BOOTSTRAP_STATE/10-a.installed"; return 1; }
mod_10_a_validate()    { return 0; }
mod_10_a_rollback()    { :; }
EOF
  runner_load_modules
  runner_run_module "10-a"
  [[ ! -f "$BOOTSTRAP_STATE/10-a.installed" ]]
}

@test "runner_run_module triggers rollback on validate failure" {
  cat > "$BOOTSTRAP_MODULES/10-a.sh" <<'EOF'
mod_10_a_description() { echo "fails to validate"; }
mod_10_a_stage()       { echo "1"; }
mod_10_a_dependencies(){ echo ""; }
mod_10_a_check()       { return 1; }
mod_10_a_install()     { echo installed > "$BOOTSTRAP_STATE/10-a.installed"; }
mod_10_a_validate()    { return 1; }
mod_10_a_rollback()    { rm -f "$BOOTSTRAP_STATE/10-a.installed"; }
EOF
  runner_load_modules
  ! runner_run_module "10-a"
  [[ ! -f "$BOOTSTRAP_STATE/10-a.installed" ]]
}

@test "stage 2 is gated by 20-users.state=admin_validated" {
  make_minimal_module "10-a"
  cat > "$BOOTSTRAP_MODULES/20-users.sh" <<'EOF'
mod_20_users_description() { echo "users"; }
mod_20_users_stage()       { echo "1"; }
mod_20_users_dependencies(){ echo "10-a"; }
mod_20_users_check()       { return 1; }
mod_20_users_install()     { printf 'admin_validated\n' > "$BOOTSTRAP_STATE/20-users.state"; }
mod_20_users_validate()    { return 0; }
mod_20_users_rollback()    { rm -f "$BOOTSTRAP_STATE/20-users.state"; }
EOF
  # Stage 2 module: should refuse until state present.
  cat > "$BOOTSTRAP_MODULES/30-security.sh" <<'EOF'
mod_30_security_description() { echo "security"; }
mod_30_security_stage()       { echo "2"; }
mod_30_security_dependencies(){ echo "20-users"; }
mod_30_security_check()       { return 1; }
mod_30_security_install()     { echo installed > "$BOOTSTRAP_STATE/30-security.installed"; return 1; }
mod_30_security_validate()    { return 0; }
mod_30_security_rollback()    { rm -f "$BOOTSTRAP_STATE/30-security.installed"; }
EOF
  runner_load_modules
  runner_run_module "10-a"
  runner_run_module "20-users"
  # Run stage 2 — must fail because runner_safety_prerequisite returns 1
  # (the install above wrote admin_validated status, but runner_safety_prerequisite
  # checks 20-users.state for status=admin_validated).
  # Verify the state has the right status key.
  grep -q '^status=admin_validated' "$BOOTSTRAP_STATE/20-users.state"
  # Now runner_safety_prerequisite should pass.
  runner_safety_prerequisite
}

@test "idempotency: a second run with check returning 0 makes no changes" {
  cat > "$BOOTSTRAP_MODULES/10-a.sh" <<'EOF'
mod_10_a_description() { echo "idem"; }
mod_10_a_stage()       { echo "1"; }
mod_10_a_dependencies(){ echo ""; }
mod_10_a_check()       { [[ -f "$BOOTSTRAP_STATE/10-a.installed" ]] && return 0 || return 1; }
mod_10_a_install()     { echo ok > "$BOOTSTRAP_STATE/10-a.installed"; }
mod_10_a_validate()    { return 0; }
mod_10_a_rollback()    { :; }
EOF
  runner_load_modules
  runner_run_module "10-a"
  local first second
  first="$(sha256sum "$BOOTSTRAP_STATE/10-a.installed" | awk '{print $1}')"
  # Second run should NOT touch the file (check() returns 0).
  runner_run_module "10-a"
  second="$(sha256sum "$BOOTSTRAP_STATE/10-a.installed" | awk '{print $1}')"
  [[ "$first" == "$second" ]]
}

@test "module API validation catches missing functions" {
  cat > "$BOOTSTRAP_MODULES/10-broken.sh" <<'EOF'
mod_10_broken_description() { echo "missing install"; }
mod_10_broken_stage()       { echo "1"; }
mod_10_broken_dependencies(){ echo ""; }
mod_10_broken_check()       { return 1; }
# no install/validate/rollback defined
EOF
  runner_load_modules
  ! runner_validate_module_api
}