#!/usr/bin/env bash
# pipelines/test.sh — bats test suite.
# Usage: ./pipelines/test.sh [bats args...]
set -Eeuo pipefail

# shellcheck source=./_lib.sh
. "$(dirname "$0")/_lib.sh"

bats_bin="$(tool_path bats)"

if (($#)); then
  step "bats: $*"
  "$bats_bin" "$@"
else
  step "bats: $REPO_ROOT/tests"
  "$bats_bin" "$REPO_ROOT/tests"
fi

ok "bats passed"
