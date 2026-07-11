# Changelog

All notable changes to BootstrapX are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-07-10

### Changed — framework refactor (one-time bootstrap → configuration management)
- **CLI transformed** to configuration-management style: `apply`, `validate`, `status`, `doctor`, `update`, `backup`, `restore`, `rollback`, `clean`, `version`. `--dry-run / --safe / --force / --verbose / --debug / --only / --stage` retained as flags on `apply / validate / status / update`.
- **User model hardened to least-privilege**:
  - `agent` sandboxed: nologin shell, password locked, no SSH keys, no sudo, owns `/srv/agent/{workspace,cache,logs,models}` with symlinks in `$HOME`.
  - `deploy` sandboxed by default: locked password, restricted sudo (reload / restart / podman pull only), nologin shell; opt in to SSH via `DEPLOY_SSH_ENABLED`.
  - `admin` retains full sudo, SSH-only, snippet at `/etc/sudoers.d/admin`.
- **Filesystem hierarchy**: new `25-filesystem` module creates `/srv/{workspace,repos,cache,artifacts,logs,backups,models}` and `/srv/agent/{workspace,cache,logs,models}` with role-based ownership.
- **AI agents moved under the `agent` account**: systemd user units (pi-agent, codex-agent, claude-agent, ollama) installed in `~/.config/systemd/user/` of `agent`, auto-restart, working dir `/srv/agent/workspace`, logs to journald.
- **Git split into its own module** (`45-git`): Git LFS, gh CLI, delta, safe.directory, signing, rebase, rerere. Removed from `50-dev`.
- **Shell split into its own module** (`55-shell`): zsh, starship, fzf, zoxide, bat, ripgrep, fd, jq, yq, tmux, direnv, fastfetch, btop. Per-user config under admin's `~/.config` and `~/.zshrc` (managed block).

### Added
- New config keys: `DEPLOY_SUDO_RESTRICTED`, `DEPLOY_SSH_ENABLED`, `SRV_ROOT`, `GIT_DEFAULT_BRANCH`, `GIT_USER_NAME`, `GIT_USER_EMAIL`, `ENABLE_ZSH`, `ENABLE_STARSHIP`, `ENABLE_TMUX`.
- AI-aware doctor checks: agent user sandbox (`nologin`, locked password, no `authorized_keys`, no sudo), `/srv` hierarchy ownership, swap, GPU detection (nvidia), linger enabled for `agent`.
- `bootstrap backup` / `bootstrap restore` for state snapshots.
- `bootstrap clean` removes transient logs and tmp files; keeps per-module backups under `state/backups/`.

### Notes
- `apply` is the new default command. Existing usage `./bootstrap.sh --safe` maps to `./bootstrap.sh apply --safe`.

## [0.1.0] - 2026-07-10

### Added
- Initial framework release: runner, staged execution (stages 0–7), and dependency-graph module loader.
- Core libraries: `log`, `config`, `system`, `fs`, `network`, `packages`, `users`, `services`, `templates`, `rollback`, `doctor`, `runner`, `ensure`.
- Idempotency helpers: `ensure_package`, `ensure_packages`, `ensure_repo`, `ensure_gpg_key`, `ensure_user`, `ensure_group`, `ensure_directory`, `ensure_file`, `ensure_template`, `ensure_line`, `ensure_block`, `ensure_symlink`, `ensure_permission`, `ensure_service_enabled`, `ensure_service_disabled`, `ensure_service_running`, `ensure_service_sshd_reload`, `ensure_sysctl`, `ensure_hostname`, `ensure_timezone`, `ensure_locale`, `ensure_cron`, `ensure_timer`, `ensure_environment_variable`, `ensure_mount`.
- Safe-bootstrap flow: `sshd -t` validation before any SSH restart; staged lockout prevention (root login stays enabled until admin validated); `--safe` (default) and `--force` flags; non-root chown no-ops gracefully.
- Modules:
  - `10-base` — apt update + base packages, hostname, timezone, locale, unattended-upgrades, chrony.
  - `20-users` — admin/deploy/agent users, SSH keys, sudoers — the safety-critical module.
  - `30-security` — SSH hardening, UFW, Fail2Ban, AppArmor, auditd, needrestart, unattended-upgrades, curated sysctl.
  - `40-podman` — rootless Podman, buildah, skopeo, fuse-overlayfs, slirp4netns, subuid/subgid, linger, registries.conf, storage.conf, sample Quadlets.
  - `50-dev` — git + delta + LFS + signing, gh, Node.js LTS (NodeSource), Bun, Python + uv + pipx + ruff + black, .NET SDK (Microsoft apt), PowerShell, workspace dirs.
  - `60-ai` — OpenClaw, Pi Coding Agent, Codex CLI, Claude Code, Ollama (optional); per-user systemd user units.
  - `70-monitoring` — btop, fastfetch, smartmontools + smartd config, vnstat, iotop, iftop, lm-sensors.
- Samples: `files/quadlets/hello.container`, `files/systemd/podman-auto-update.{service,timer}`, `templates/sudoers-admin.tpl`, `templates/boot_profile.template`.
- Tests: Bats suites for helpers (`tests/helpers.bats`), runner (`tests/runner.bats`), idempotency (`tests/idempotency.bats`), and per-module (`tests/modules/{10-base,20-users}.bats`).
- CI: GitHub Actions workflow running `shellcheck`, `shfmt`, `markdownlint`, `yamllint`, `bats`, plus a doctor smoke test.
- Release workflow: `.github/workflows/release.yml` produces a tagged tarball on `v*.*.*` pushes.
- Documentation: README, INSTALL, CONFIGURATION, ARCHITECTURE, SECURITY, MODULE_DEVELOPMENT, TROUBLESHOOTING, CONTRIBUTING, docs/README.
- Example config: `examples/bootstrap.conf.example`.
- `Makefile` for `make shellcheck`, `make shfmt`, `make bats`, `make test`, `make doctor`.

[Unreleased]: https://github.com/OWNER/bootstrapx/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/OWNER/bootstrapx/releases/tag/v0.2.0
[0.1.0]: https://github.com/OWNER/bootstrapx/releases/tag/v0.1.0