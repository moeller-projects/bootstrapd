# Architecture

BootstrapX is a small declarative configuration-management framework. The whole thing is one entry script, thirteen libraries, and a directory of self-describing modules. The framework's job is to run the same set of idempotent modules whenever state drifts, with the same observable end state.

## Flow

```
bootstrap.sh <command> [options]
   │
   ▼
preflight (stage 0, on apply)
   │ distro / arch / root / net / dns / disk / memory / time
   ▼
load bootstrap.conf
   │
   ▼
discover modules in modules/*.sh
   │
   ▼
topological sort by dependencies()
   │
   ▼
for each module (in order, gated by stage / --only):
   ├─ check()             ← returns 0 = already satisfied
   │                         1 = install() is required
   │                         2 = forced re-install
   ├─ install()            ← only runs when check() ≠ 0
   │     │
   │     ▼ every change goes through an ensure_* helper:
   │       - backup existing file (lib/fs.sh → backup_file)
   │       - register rollback (lib/rollback.sh → register)
   │       - apply change
   │       - log
   ├─ validate()           ← must return 0 or rollback fires
   └─ record state (state/<module>.state)
```

## Commands

| Command | Maps to | Description |
|---|---|---|
| `apply` | preflight + runner_run_all | Reconcile to desired state |
| `validate` | runner_discover + per-module check() | Detect drift without applying |
| `status` | read state files | Print last-known module status |
| `doctor` | doctor_run | 30+ checks, Markdown + JSON |
| `update` | git pull + apply | Pull latest framework and re-apply |
| `backup` | tar state/ + bootstrap.conf | Snapshot |
| `restore` | tar extract | Restore from snapshot |
| `rollback` | runner_rollback_all | Undo module(s) |
| `clean` | find + delete | Remove transient state |

## Modules

The module set is intentionally narrow. Each module is a single Bash file under `modules/`. The runner discovers them, sources them once, and calls functions whose names start with `mod_<NN>_<name>_`.

### Module roster

| ID | Stage | Purpose |
|---|---|---|
| `10-base` | 1 | apt update + base packages; hostname, timezone, locale; chrony; unattended-upgrades |
| `20-users` | 1 | Least-privilege users: admin (full sudo + SSH), deploy (restricted sudo, locked), agent (nologin, no SSH, no sudo) |
| `25-filesystem` | 1 | `/srv` hierarchy with role-based ownership and `/srv/agent` runtime dirs |
| `30-security` | 2 | SSH hardening, UFW, Fail2Ban, AppArmor, auditd, needrestart, curated sysctl |
| `40-podman` | 4 | Rootless Podman, buildah, skopeo, fuse-overlayfs, slirp4netns, subuid/subgid, linger, registries.conf, storage.conf |
| `45-git` | 3 | git + LFS + gh CLI + delta; per-user global config (admin + deploy) |
| `50-dev` | 3 | Language runtimes: Node LTS, Bun, Python, uv, pipx, .NET SDK, PowerShell |
| `55-shell` | 3 | Modern shell: zsh, starship, fzf, zoxide, bat, ripgrep, fd, jq, yq, tmux, direnv, fastfetch, btop |
| `60-ai` | 5 | OpenClaw, Pi, Codex CLI, Claude Code, Ollama — installed as systemd user services under the `agent` account |
| `70-monitoring` | 6 | btop, fastfetch, smartmontools + smartd config, vnstat, iotop, iftop, lm-sensors |

The numeric prefix is **not** authoritative for execution order — `dependencies()` is. The prefix exists so `ls modules/` reflects the intended order.

### Module interface

```bash
mod_NN_name_description()  { echo "Short description"; }
mod_NN_name_stage()        { echo "1"; }
mod_NN_name_dependencies() { echo "10-base 30-security"; }
mod_NN_name_check()        { ... return 0; }     # 0 = already done
mod_NN_name_install()      { ... }                # apply changes (idempotent)
mod_NN_name_validate()     { ... return 0; }      # post-install sanity check
mod_NN_name_rollback()     { ... }                # undo install()
```

`check()` must be **fast and read-only**. No file mutations, no service restarts, no package installs.

`install()` always goes through `ensure_*` helpers. Never call `apt`, `systemctl`, `useradd`, `cp`, `mv`, or `echo >>` directly. Wrap risky operations in backup + register.

`validate()` returns 0 only if every post-condition holds. The runner treats non-zero as a failure and rolls the module back.

## Idempotency model

Every mutation flows through an `ensure_*` helper. The helper:

1. Inspects current state.
2. Returns immediately if the desired state is already met.
3. Otherwise:
   - Backs up the file being changed (if any).
   - Registers a rollback.
   - Applies the change.
   - Verifies the change took effect.

Examples:

- `ensure_user alice` is a no-op if `id alice` already works.
- `ensure_file /etc/motd "Welcome\n"` overwrites only if the contents differ.
- `ensure_line /etc/ssh/sshd_config "PermitRootLogin no"` adds the line if missing, replaces it if it differs.
- `ensure_service_enabled ssh` runs `systemctl enable ssh` only if `is-enabled` is not `enabled`.

## Dry-run

`--dry-run` sets `BOOTSTRAP_DRY_RUN=1`. The helpers print what they would do instead of doing it. Modules may short-circuit: `check()` still runs, but `install()` only emits log lines and returns 0.

## Rollback

Every file backup is logged in `state/rollback.tsv`. On failure, the runner iterates that file in reverse and restores each backup. New backups take precedence; missing backups are skipped with a warning.

`./bootstrap.sh rollback MODULE` rolls back only that module. `./bootstrap.sh rollback` rolls back everything in reverse order.

## State

`state/<module>.state` contains:

```
status=ok
installed_at=2026-07-10T08:13:42Z
module_checksum=...
```

The runner checks the state file before invoking `check()`. A module that succeeded last run can be skipped. Pass `--force` to ignore state.

`./bootstrap.sh status` prints the table:

```
MODULE                 STATUS                 INSTALLED_AT
------------------------------------------------------------
10-base                ok                     2026-07-10T08:13:42Z
20-users               admin_validated        2026-07-10T08:14:00Z
```

## Configuration loading

`lib/config.sh` reads `bootstrap.conf` (or `--config FILE`) once and exports every key. A schema declares defaults and types. Unknown keys log a warning but are accepted (forward-compatible).

## Logging

`lib/log.sh` writes to `state/bootstrap.log` and to the terminal with ANSI colors when stderr is a TTY. Levels: `INFO`, `WARN`, `ERROR`, `SUCCESS`, `DEBUG`. `--debug` enables `DEBUG`. `--verbose` enables `INFO` and up.

## Safety

`sshd -t` is the gate. `ensure_service_sshd_reload` refuses to restart sshd if `sshd -t` exits non-zero. The runner refuses to enter stage 2 unless stage 1 ended with the admin user successfully authenticated.

The `agent` user is sandboxed by construction: `passwd -l` (locked), `/usr/sbin/nologin`, no `~/.ssh/authorized_keys`, no sudo. The doctor validates every one of these properties at runtime.

## Backups and restores

`./bootstrap.sh backup` snapshots `state/` and `bootstrap.conf` to a gzipped tarball under `./backups/` (or a directory you specify). `./bootstrap.sh restore <file>` extracts it back. The runner itself does not depend on backups; backups are a safety net for the operator.

## Extensibility

Adding a module is a single new file under `modules/`. No registration step, no central manifest. See [MODULE_DEVELOPMENT.md](MODULE_DEVELOPMENT.md).