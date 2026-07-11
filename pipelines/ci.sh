#!/usr/bin/env bash
# pipelines/ci.sh — full CI pipeline. Mirrors .github/workflows/ci.yml.
# Runs every step; first failure aborts. Each step can also be run standalone
# (e.g. ./pipelines/lint.sh).
set -Eeuo pipefail

# shellcheck source=./_lib.sh
. "$(dirname "$0")/_lib.sh"

cd "$REPO_ROOT"

step "ci: lint (shellcheck + shfmt)"
"$PIPELINES_DIR/lint.sh"

step "ci: tests (bats)"
"$PIPELINES_DIR/test.sh"

step "ci: doctor (smoke test)"
"$PIPELINES_DIR/doctor.sh"

step "ci: markdownlint"
"$PIPELINES_DIR/lint-docs.sh"

step "ci: yamllint"
"$PIPELINES_DIR/lint-yml.sh"

ok "ci: all pipelines passed"
