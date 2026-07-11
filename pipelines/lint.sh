#!/usr/bin/env bash
# pipelines/lint.sh — shellcheck + shfmt.
# Usage: ./pipelines/lint.sh [files...]
#   With no args: lints every .sh in the repo.
#   With args:    lints only the given files.
set -Eeuo pipefail

# shellcheck source=./_lib.sh
. "$(dirname "$0")/_lib.sh"

if (($#)); then
  targets=("$@")
else
  mapfile -t targets < <(sh_files)
fi

((${#targets[@]} > 0)) || die "no shell files to lint"

sc="$(tool_path shellcheck)"
fmt="$(tool_path shfmt)"

step "shellcheck: ${#targets[@]} file(s)"
fail=0
for f in "${targets[@]}"; do
  if ! "$sc" --severity=warning --shell=bash -- "$f"; then
    fail=1
  fi
done
((fail == 0)) || die "shellcheck found issues"

step "shfmt -d: ${#targets[@]} file(s)"
if ! "$fmt" -d -i 2 -ci -fn "${targets[@]}"; then
  die "shfmt would reformat the above; run 'shfmt -w -i 2 -ci -fn <file>' to fix"
fi

ok "lint passed (${#targets[@]} files)"
