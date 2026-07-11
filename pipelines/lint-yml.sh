#!/usr/bin/env bash
# pipelines/lint-yml.sh — yamllint on every .yml/.yaml in the repo.
set -Eeuo pipefail

# shellcheck source=./_lib.sh
. "$(dirname "$0")/_lib.sh"

yl="$(tool_path yamllint)"

mapfile -t files < <(yml_files)
((${#files[@]} > 0)) || die "no yaml files to lint"

step "yamllint: ${#files[@]} file(s)"
"$yl" -c "$REPO_ROOT/.yamllint.yml" "${files[@]}"

ok "yamllint passed"
