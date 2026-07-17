#!/usr/bin/env bash
set -Eeuo pipefail

repo_url="https://github.com/moeller-projects/bootstrapd.git"
dest_dir="/opt/bootstrapd"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  printf 'kickstart.sh: run as root\n' >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  apt-get update
  apt-get install -y git
fi

if [[ -d "$dest_dir/.git" ]]; then
  git -C "$dest_dir" pull --ff-only
else
  if [[ -e "$dest_dir" ]]; then
    printf 'kickstart.sh: %s exists and is not a git checkout\n' "$dest_dir" >&2
    exit 1
  fi
  git clone "$repo_url" "$dest_dir"
fi

cd "$dest_dir"

if [[ ! -r bootstrap.conf ]]; then
  cp examples/bootstrap.conf.example bootstrap.conf
  "${EDITOR:-vi}" bootstrap.conf
fi

./bootstrap.sh apply --safe
