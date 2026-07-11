# BootstrapX

Idempotent, modular, production-grade Linux server bootstrap framework in portable Bash.

BootstrapX brings a fresh Ubuntu 24.04 LTS or Debian 12 server from a raw `root@server` SSH session to a hardened, fully provisioned AI-development workstation — without ever risking an SSH lockout.

## Features

- **Idempotent**: run it once or one hundred times — same result. Every change goes through an `ensure_*` helper that tests the desired state first.
- **Staged execution**: stages 0–7 (preflight → safe bootstrap → security → developer tools → containers → AI tooling → monitoring → validation).
- **Safety-first**: SSH configuration is validated with `sshd -t` before any restart. Root login is only disabled after the new admin user has been verified to log in.
- **Modular**: every capability is a self-describing module with `dependencies`, `check`, `install`, `validate`, `rollback`.
- **Configuration-driven**: every tunable lives in `bootstrap.conf`. Nothing is hardcoded.
- **Recoverable**: every file change is backed up and registered for automatic rollback on failure. Resume after interruption.
- **Dry-run and debug**: `--dry-run` plans, `--debug` traces, `--verbose` narrates.
- **Zero runtime dependencies** beyond Bash 5+, `apt`, and `systemctl` (the user is expected to provide these via the OS). The CI uses `shellcheck`, `shfmt`, and `bats` to enforce quality.

## Targets

- Ubuntu 24.04 LTS, Debian 12 (bookworm)
- x86_64, ARM64 (aarch64)

## Quick start

```bash
git clone https://github.com/OWNER/bootstrapx.git
cd bootstrapx
cp examples/bootstrap.conf.example bootstrap.conf
$EDITOR bootstrap.conf             # set HOSTNAME, ADMIN_USER, SSH_PUBLIC_KEYS, etc.
sudo ./bootstrap.sh --safe        # safe-bootstrap (default)
sudo ./bootstrap.sh doctor        # validate
```

After the safe-bootstrap stage succeeds, reconnect as the admin user and re-run:

```bash
ssh admin@server
sudo ./bootstrap.sh --safe        # continues into stage 2 (security hardening)
```

## Documentation

| Document | Purpose |
|---|---|
| [INSTALL.md](INSTALL.md) | Install BootstrapX, run it for the first time |
| [CONFIGURATION.md](CONFIGURATION.md) | Every `bootstrap.conf` knob |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Stages, modules, dependency graph, idempotency model |
| [SECURITY.md](SECURITY.md) | Threat model, safe-bootstrap flow, SSH lockout prevention |
| [MODULE_DEVELOPMENT.md](MODULE_DEVELOPMENT.md) | Author a new module |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common failures and recovery |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Code style, testing, PR flow |

## Project status

This is the 0.1.0 release — **framework + foundation**. It ships the runner, all `ensure_*` helpers, and two reference modules (`10-base`, `20-users`) that exercise the safe-bootstrap path. Subsequent 0.x releases add the remaining modules (containers, AI, monitoring, security hardening) following the module development guide.

## License

MIT — see [LICENSE](LICENSE).