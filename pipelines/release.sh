#!/usr/bin/env bash
# pipelines/release.sh — build a versioned tarball, like .github/workflows/release.yml.
# Usage: ./pipelines/release.sh [output-dir]
set -Eeuo pipefail

# shellcheck source=./_lib.sh
. "$(dirname "$0")/_lib.sh"

cd "$REPO_ROOT"

version="$(cat VERSION)"
[[ -n "$version" ]] || die "VERSION file is empty"

out_dir="${1:-$REPO_ROOT/release}"
mkdir -p "$out_dir"
tarball="$out_dir/bootstrapx-${version}.tar.gz"

step "building $tarball"
tar --exclude='./release' --exclude='./.git' --exclude='./state/backups' \
  --exclude='./pipelines/.tools' --exclude='./backups' \
  -czf "$tarball" .

if [[ ! -s "$tarball" ]]; then
  die "tarball not produced"
fi

size="$(du -h "$tarball" | awk '{print $1}')"
ok "wrote $tarball ($size)"
