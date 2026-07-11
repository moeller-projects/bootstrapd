#!/usr/bin/env bash
# pipelines/doctor.sh — run `bootstrap doctor` as a smoke test.
# Boots a minimal bootstrap.conf so doctor has something to read.
set -Eeuo pipefail

# shellcheck source=./_lib.sh
. "$(dirname "$0")/_lib.sh"

cd "$REPO_ROOT"

# Generate a minimal config if none is present.
if [[ ! -r bootstrap.conf ]]; then
  step "no bootstrap.conf; copying from examples/"
  cp examples/bootstrap.conf.example bootstrap.conf
fi

# doctor exits 0 on success even if individual checks fail. We just need
# the script to not crash and the JSON report to be well-formed when --json
# is passed.
step "bootstrap doctor"
./bootstrap.sh doctor

step "bootstrap doctor --json"
./bootstrap.sh doctor --json

if [[ -s "$REPO_ROOT/state/doctor.json" ]]; then
  ok "doctor.json produced ($(wc -c <"$REPO_ROOT/state/doctor.json") bytes)"
else
  die "doctor.json missing or empty"
fi
