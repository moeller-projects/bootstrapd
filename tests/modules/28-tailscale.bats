#!/usr/bin/env bats
# tests/modules/28-tailscale.bats — module-level tests for 28-tailscale.

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

  ensure_service_enabled() { :; }
  ensure_service_running() { :; }
  ensure_service_disabled() { :; }
  svc_active() { return 0; }
  export -f ensure_service_enabled ensure_service_running ensure_service_disabled svc_active

  ENABLE_TAILSCALE=false
  TAILSCALE_AUTH_KEY=
  BOOTSTRAP_DRY_RUN=0
  BOOTSTRAP_NON_INTERACTIVE=1
  export ENABLE_TAILSCALE TAILSCALE_AUTH_KEY BOOTSTRAP_DRY_RUN BOOTSTRAP_NON_INTERACTIVE

  . "$BOOTSTRAP_MODULES/28-tailscale.sh"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "28-tailscale: all required functions are defined" {
  declare -F mod_28_tailscale_description
  declare -F mod_28_tailscale_stage
  declare -F mod_28_tailscale_dependencies
  declare -F mod_28_tailscale_check
  declare -F mod_28_tailscale_install
  declare -F mod_28_tailscale_validate
  declare -F mod_28_tailscale_rollback
}

@test "28-tailscale: stage is 2, depends on 20-users" {
  [[ "$(mod_28_tailscale_stage)" == "2" ]]
  [[ "$(mod_28_tailscale_dependencies)" == *"20-users"* ]]
}

@test "28-tailscale: check is a no-op when disabled" {
  ! mod_28_tailscale_check
}

@test "28-tailscale: dry-run install succeeds when enabled" {
  ENABLE_TAILSCALE=true
  BOOTSTRAP_DRY_RUN=1
  mod_28_tailscale_install
}

@test "28-tailscale: validate is a no-op when disabled" {
  mod_28_tailscale_validate
}
