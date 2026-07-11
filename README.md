# BootstrapX

Idempotent, declarative, production-grade configuration management framework for Linux AI development servers, written in portable Bash.

BootstrapX manages the **full lifecycle** of an Ubuntu 24.04 LTS or Debian 12 server: initial provisioning, ongoing reconciliation, validation, backup, and rollback. Every change goes through a single, tested set of helpers; every action is recorded; every failure is recoverable.

```
$ bootstrap status
MODULE                STATUS                 INSTALLED_AT
------------------------------------------------------------
10-base               ok                     2026-07-10T10:42:01Z
20-users              admin_validated        2026-07-10T10:43:18Z
25-filesystem         ok                     2026-07-10T10:43:55Z
30-security           ok                     2026-07-10T10:51:09Z
40-podman             ok                     2026-07-10T10:55:33Z
45-git                ok                     2026-07-10T10:58:11Z
50-dev                ok                     2026-07-10T11:02:48Z
55-shell              ok                     2026-07-10T11:05:01Z
60-ai                 ok                     2026-07-10T11:09:25Z
70-monitoring         ok                     2026-07-10T11:11:55Z
```

## Why

Long-lived AI development servers drift. Tools get upgraded, kernels change, `apt` autoupgrades pull in patches that change defaults, and the original bootstrap becomes stale. BootstrapX is built around the same idea as Terraform or NixOS: **describe the desired state, reconcile on demand, observe the delta**.

## CLI

```
bootstrap.sh <command> [options]

apply                  Reconcile the system to bootstrap.conf
validate               Verify modules and config without applying
status                 Show the recorded state of every module
doctor                 Run the full diagnostic suite (Markdown + JSON)
update                 Pull the latest framework and re-apply
backup [DIR]           Snapshot the state directory
restore SNAPSHOT       Restore state from a snapshot tarball
rollback [MODULE]      Roll back changes
clean                  Remove transient logs and tmp files
version                Print version
```

Common options on `apply/validate/status/update`: `--safe`, `--force`, `--dry-run`, `--non-interactive`, `--verbose`, `--debug`, `--only MODULE`, `--stage N`, `--config FILE`.

## User model (least privilege)

| User | Purpose | Shell | SSH | Sudo |
|---|---|---|---|---|
| `root` | bootstrap + emergency only | n/a | disabled after stage 1 | n/a |
| `admin` | primary operator | bash/zsh | key only | full (NOPASSWD) |
| `deploy` | CI/CD | nologin | off by default | restricted (reload/restart/podman pull only) |
| `agent` | AI tooling runtime | nologin | never | never |

AI applications always run under `agent` via systemd user services; they never execute as `admin`.

## Filesystem

Shared runtime lives under `/srv`:

```
/srv/workspace      admin-owned, group-writable
/srv/repos          admin:deploy
/srv/cache          shared
/srv/artifacts      shared (build outputs, container images)
/srv/logs           shared (service logs)
/srv/backups        root only (snapshot rsync target)
/srv/models         agent-owned (LLM weights)
/srv/agent/{workspace,cache,logs,models}  agent-owned runtime
```

Personal dotfiles and repos stay under `/home/<user>`.

## Quick start

```bash
git clone https://github.com/OWNER/bootstrapx.git /opt/bootstrapx
cd /opt/bootstrapx
cp examples/bootstrap.conf.example bootstrap.conf
$EDITOR bootstrap.conf         # set HOSTNAME, ADMIN_USER, SSH_PUBLIC_KEYS, GIT_USER_EMAIL

# Fresh server: as root, run apply. Root login stays enabled.
sudo ./bootstrap.sh apply --safe

# Reconnect as admin in a NEW terminal.
ssh admin@server
cd /opt/bootstrapx
sudo ./bootstrap.sh apply --safe    # continues into stage 2 (locks root out)

# Inspect state.
sudo ./bootstrap.sh status
sudo ./bootstrap.sh doctor --json
```

## Documentation

| Document | Purpose |
|---|---|
| [INSTALL.md](INSTALL.md) | Install BootstrapX, run it for the first time |
| [CONFIGURATION.md](CONFIGURATION.md) | Every `bootstrap.conf` knob |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Stages, modules, dependency graph, idempotency model |
| [SECURITY.md](SECURITY.md) | Threat model, safe-bootstrap flow, SSH lockout prevention, agent sandbox |
| [MODULE_DEVELOPMENT.md](MODULE_DEVELOPMENT.md) | Author a new module |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common failures and recovery |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Code style, testing, PR flow |

## License

MIT — see [LICENSE](LICENSE).