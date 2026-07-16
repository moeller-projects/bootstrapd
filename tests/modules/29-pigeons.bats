#!/usr/bin/env bats
# tests/modules/29-pigeons.bats — module-level tests for 29-pigeons.

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

  ENABLE_PIGEONS=false
  BOOTSTRAP_DRY_RUN=0
  BOOTSTRAP_VERBOSE=0
  BOOTSTRAP_DEBUG=0
  export ENABLE_PIGEONS BOOTSTRAP_DRY_RUN BOOTSTRAP_VERBOSE BOOTSTRAP_DEBUG

  . "$BOOTSTRAP_MODULES/29-pigeons.sh"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "29-pigeons: all required functions are defined" {
  declare -F mod_29_pigeons_description
  declare -F mod_29_pigeons_stage
  declare -F mod_29_pigeons_dependencies
  declare -F mod_29_pigeons_check
  declare -F mod_29_pigeons_install
  declare -F mod_29_pigeons_validate
  declare -F mod_29_pigeons_rollback
}

@test "29-pigeons: stage is 2, depends on 20-users" {
  [[ "$(mod_29_pigeons_stage)" == "2" ]]
  [[ "$(mod_29_pigeons_dependencies)" == *"20-users"* ]]
}

@test "29-pigeons: check is a no-op when disabled" {
  mod_29_pigeons_check
}

@test "29-pigeons: dry-run install succeeds when enabled" {
  ENABLE_PIGEONS=true
  BOOTSTRAP_DRY_RUN=1
  mod_29_pigeons_install
}

@test "29-pigeons: validate is a no-op when disabled" {
  mod_29_pigeons_validate
}
