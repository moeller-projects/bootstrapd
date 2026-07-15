# New server setup

## How-to

This guide shows the first-time bootstrap flow for a fresh Ubuntu 24.04 LTS or Debian 12 server.

## Prerequisites

- A fresh server with SSH access as `root`
- Bash 5.x, `apt`, `systemctl`, and `sshd` available on the target system
- Outbound HTTPS access to distro mirrors and package sources
- Your SSH public key ready for the admin account

## What BootstrapX does

BootstrapX is a directory of portable Bash files. There is no installer or daemon. The repo is cloned onto the server, configured with `bootstrap.conf`, and then run with `bootstrap.sh`.

The first run is intentionally split into two stages:

- Stage 1 creates the admin user, installs SSH keys, and configures sudo while leaving root login enabled.
- Stage 2 only runs after you reconnect as the new admin user and confirms the handoff is safe before hardening SSH.

## 1) Connect as root

Start from the provider console or SSH:

```bash
ssh root@your-new-server
```

If root login is not available yet, use whatever bootstrap console the provider gives you and become root first.

## 2) Clone the repo and configure it

```bash
git clone https://github.com/OWNER/bootstrapx.git /opt/bootstrapx
cd /opt/bootstrapx
cp examples/bootstrap.conf.example bootstrap.conf
$EDITOR bootstrap.conf
```

At minimum, set these values:

- `HOSTNAME` — the server hostname you want
- `TIMEZONE` — for example `Europe/Berlin`
- `LOCALE` — for example `en_US.UTF-8`
- `ADMIN_USER` — the primary human login, usually `admin`
- `SSH_PUBLIC_KEYS` — one key per line; these keys are installed for `ADMIN_USER`

Common optional settings:

- `DEPLOY_USER` and `DEPLOY_SSH_ENABLED` if you want a CI/CD account
- `AGENT_USER` if you plan to run AI tooling on the host
- `ENABLE_PODMAN`, `ENABLE_GITHUB_CLI`, `ENABLE_MONITORING`, and the other feature toggles in `bootstrap.conf.example`

By default, BootstrapX installs Tailscale during the handoff run. If you want unattended enrollment, set `TAILSCALE_AUTH_KEY`; if you do not want Tailscale on a server, set `ENABLE_TAILSCALE=false`.

`ENABLE_PIGEONS=true` installs the optional Pigeons roost service.

## 3) First run: safe bootstrap

Run the framework in safe mode:

```bash
sudo ./bootstrap.sh --safe
```

What happens on this run:

1. Preflight checks verify distro, architecture, root access, network, DNS, disk, and memory.
2. Base packages are installed.
3. The admin user is created.
4. The admin SSH public keys are installed.
5. Passwordless sudo is configured for the admin user.
6. SSH configuration is validated with `sshd -t` before any reload.
7. Root login stays enabled.
8. The runner asks you to reconnect as the admin user before it continues.

Do not skip the reconnection step.

## 4) Reconnect as the admin user

Open a second terminal and log in as the new admin account:

```bash
ssh admin@your-new-server
cd /opt/bootstrapx
sudo ./bootstrap.sh --safe
```

This second run completes the handoff. The runner confirms the admin account is usable before it disables root login and applies the remaining stages.

## 5) Verify the host

After the bootstrap completes, run the diagnostics:

```bash
sudo ./bootstrap.sh doctor
```

This prints a human-readable report and writes machine-readable output to `state/doctor.json`.

Useful follow-ups:

```bash
sudo ./bootstrap.sh status
sudo ./bootstrap.sh validate
```

- `status` shows the recorded state of each module.
- `validate` checks the desired state without applying changes.

## 6) Optional: preview first

If you want to see what would happen before touching the machine:

```bash
sudo ./bootstrap.sh --dry-run --verbose
```

Dry-run is read-only.

## 7) Optional: roll back

If you want to undo BootstrapX-managed changes later:

```bash
sudo ./bootstrap.sh rollback
```

That reverts BootstrapX changes in reverse order. After that, you can remove the repo directory if you no longer need it.

## Operational notes

- Re-running `sudo ./bootstrap.sh --safe` is the normal upgrade path. Modules only change what drifted.
- Keep `bootstrap.conf` under version control only if the secrets and host-specific values are handled safely.
- Stage 2 is the dangerous part: it hardens SSH and disables root login only after the admin handoff is confirmed.
- If you customize SSH settings, the framework still validates them with `sshd -t` before reload.

## Minimal checklist

- [ ] root SSH access works
- [ ] repo cloned to the server
- [ ] `bootstrap.conf` edited
- [ ] admin SSH key added
- [ ] first `--safe` run completed
- [ ] reconnected as admin
- [ ] second `--safe` run completed
- [ ] `doctor` passed
