# Architecture

BootstrapX is intentionally small. The whole framework is one entry script, twelve libraries, and a directory of self-describing modules.

## Flow

```
bootstrap.sh
   │
   ▼
preflight (stage 0)
   │ distro / arch / root / net / dns / disk / memory
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
for each module (in order, gated by stage):
   ├─ check()             ← returns 0 if already satisfied
   │                         1 if install() is required
   │                         2 if forced re-install
   ├─ install()            ← only runs when check() ≠ 0
   │     │
   │     ▼ every change goes through an ensure_* helper:
   │       - backup existing file (lib/fs.sh → backup_file)
   │       - register rollback (lib/rollback.sh → register)
   │       - apply change
   │       - log
   ├─ validate()           ← must return 0 or rollback fires
   └─ record state (state/<module>.state)
   ▼
doctor (on demand)
```

## Stages

Stages are coarse-grained phases. A module declares which stage it belongs to; the runner processes them in order.

| Stage | Name | Purpose | May lock you out? |
|---|---|---|---|
| 0 | Preflight | Read-only checks. | No |
| 1 | Safe bootstrap | Update OS, create admin user, install SSH keys, sudo. Root login stays enabled. | No |
| 2 | Security | Disable root, disable password auth, UFW, fail2ban, AppArmor, sysctl. | Yes — only fires after admin is validated. |
| 3 | Developer | Node, Bun, Python, .NET, PowerShell, shell utilities. | No |
| 4 | Containers | Podman rootless, buildah, skopeo, Quadlets. | No |
| 5 | AI | OpenClaw, Pi, Codex, Claude. | No |
| 6 | Monitoring | btop, smartmontools, vnstat. | No |
| 7 | Validation | Diagnostics report. | No |

## Module interface

Every module is `modules/NN-name.sh` where `NN` is the load order. The runner sources the file once and calls functions whose names start with `mod_<NN>_`.

```bash
mod_20_dependencies() { echo "10-base"; }     # space-separated module IDs
mod_20_stage()        { echo "1"; }
mod_20_check()        { return 0; }           # 0 = already done
mod_20_install()      { ensure_user "$ADMIN_USER"; ...; }
mod_20_validate()     { id "$ADMIN_USER" >/dev/null; }
mod_20_rollback()     { userdel -r "$ADMIN_USER" 2>/dev/null || true; }
mod_20_description()  { echo "Create admin/deploy/agent users and SSH keys"; }
```

The `dependencies()` return is space-separated; the runner does a topological sort. Cycles are detected and abort the run.

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

Every file backup is logged in `state/rollback.tsv` (TSV: timestamp, module, path, backup path). On failure, the runner iterates that file in reverse and restores each backup. New backups take precedence; missing backups are skipped with a warning.

`./bootstrap.sh rollback MODULE` rolls back only that module. `./bootstrap.sh rollback` rolls back everything.

## State

`state/<module>.state` contains:

```
status=ok
installed_at=2026-07-10T08:13:42Z
checksum=...
```

The runner checks `state/<module>.state` before invoking `check()` — a module that succeeded last run can be skipped if `--only` was not given. Pass `--force` to ignore state.

## Configuration loading

`lib/config.sh` reads `bootstrap.conf` (or `--config FILE`) once and exports every key. A small schema in `lib/config.sh` declares defaults and types. Unknown keys log a warning but are accepted (forward-compatible).

## Logging

`lib/log.sh` writes to `state/bootstrap.log` (rotated daily) and to the terminal with ANSI colors when stderr is a TTY. Levels: `INFO`, `WARN`, `ERROR`, `SUCCESS`, `DEBUG`. `--debug` enables `DEBUG`. `--verbose` enables `INFO` and up. Quiet is the default.

## Safety

`sshd -t` is the gate. `ensure_service_running ssh` and `ensure_service_reload ssh` refuse to restart the service if `sshd -t` exits non-zero. The runner refuses to enter stage 2 unless stage 1 ended with the admin user successfully authenticated against a live `sshd` (checked by parsing `state/20-users.state` and, optionally, by reading `last -f /var/log/wtmp` if available).

## Extensibility

Adding a module is a single new file under `modules/`. No registration step, no central manifest. See [MODULE_DEVELOPMENT.md](MODULE_DEVELOPMENT.md).