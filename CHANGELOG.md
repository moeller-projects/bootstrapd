# Changelog

All notable changes to BootstrapX are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-10

### Added
- Initial framework release: runner, staged execution (stages 0–7), and dependency-graph module loader.
- Core libraries: `log`, `config`, `system`, `fs`, `network`, `packages`, `users`, `services`, `templates`, `rollback`, `doctor`, `runner`, `ensure`.
- Idempotency helpers: `ensure_package`, `ensure_packages`, `ensure_repo`, `ensure_gpg_key`, `ensure_user`, `ensure_group`, `ensure_directory`, `ensure_file`, `ensure_template`, `ensure_line`, `ensure_block`, `ensure_symlink`, `ensure_permission`, `ensure_service_enabled`, `ensure_service_disabled`, `ensure_service_running`, `ensure_service_sshd_reload`, `ensure_sysctl`, `ensure_hostname`, `ensure_timezone`, `ensure_locale`, `ensure_cron`, `ensure_timer`, `ensure_environment_variable`, `ensure_mount`.
- Safe-bootstrap flow: `sshd -t` validation before any SSH restart; staged lockout prevention (root login stays enabled until admin validated); `--safe` (default) and `--force` flags; non-root chown no-ops gracefully.
- CLI: `--safe`/`--force`, `--dry-run`, `--non-interactive`, `--verbose`, `--debug`, `--only`, `--stage`, `--config`, plus `doctor`/`resume`/`rollback`/`version` subcommands.
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

### Notes
- All seven stages are implemented. Further hardening (full AppArmor profile authoring, auditd ruleset curation, Tailscale enrollment, Caddy reverse-proxy config) is the natural next increment; the framework supports them as new modules per `MODULE_DEVELOPMENT.md`.

[Unreleased]: https://github.com/OWNER/bootstrapx/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/OWNER/bootstrapx/releases/tag/v0.1.0