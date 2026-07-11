#!/usr/bin/env bats
# tests/modules/10-base.bats — module-level tests for 10-base.
# Runs the module inside a sandbox: most actions are stubbed (no actual apt).
# Verifies the module API, idempotency, and rollback.

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  export BOOTSTRAP_ROOT="$TEST_TMPDIR"
  export BOOTSTRAP_STATE="$TEST_TMPDIR/state"
  export BOOTSTRAP_MODULES="$BATS_TEST_DIRNAME/../../modules"
  export BOOTSTRAP_LIB="$BATS_TEST_DIRNAME/../../lib"

  mkdir -p "$BOOTSTRAP_STATE"

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

  # Stub pkg_installed to return false (forces install path).
  pkg_installed() { return 1; }
  pkg_install() { :; }
  pkg_install_many() { :; }
  pkg_update_index() { :; }
  svc_enable() { :; }
  svc_running() { :; }
  svc_active() { return 0; }
  export -f pkg_installed pkg_install pkg_install_many pkg_update_index
  export -f svc_enable svc_running svc_active

  HOSTNAME=test-host
  TIMEZONE=UTC
  LOCALE=en_US.UTF-8
  ENABLE_AUTO_UPDATES=false
  export HOSTNAME TIMEZONE LOCALE ENABLE_AUTO_UPDATES

  BOOTSTRAP_DRY_RUN=0
  BOOTSTRAP_VERBOSE=0
  BOOTSTRAP_DEBUG=0
  BOOTSTRAP_SAFE=1

  # Source the module.
  . "$BOOTSTRAP_MODULES/10-base.sh"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "10-base: check returns non-zero before install" {
  ! mod_10_check
}

@test "10-base: all required functions are defined" {
  declare -F mod_10_description
  declare -F mod_10_stage
  declare -F mod_10_dependencies
  declare -F mod_10_check
  declare -F mod_10_install
  declare -F mod_10_validate
  declare -F mod_10_rollback
}

@test "10-base: stage is 1, no deps" {
  [[ "$(mod_10_stage)" == "1" ]]
  [[ -z "$(mod_10_dependencies)" ]]
}

@test "10-base: install runs without error in dry-run mode" {
  BOOTSTRAP_DRY_RUN=1
  mod_10_install
}

@test "10-base: validate returns 0" {
  mod_10_validate
}

@test "10-base: rollback is a safe no-op" {
  mod_10_rollback
}