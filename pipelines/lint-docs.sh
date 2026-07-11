#!/usr/bin/env bash
# pipelines/lint-docs.sh — markdownlint-cli on every .md in the repo.
set -Eeuo pipefail

# shellcheck source=./_lib.sh
. "$(dirname "$0")/_lib.sh"

mdl="$(tool_path markdownlint)"

mapfile -t files < <(md_files)
((${#files[@]} > 0)) || die "no markdown files to lint"

step "markdownlint: ${#files[@]} file(s)"
if [[ -f "$REPO_ROOT/.markdownlint.jsonc" ]]; then
  "$mdl" --config "$REPO_ROOT/.markdownlint.jsonc" "${files[@]}"
else
  "$mdl" "${files[@]}"
fi

ok "markdownlint passed"
