# Install

BootstrapX is shipped as a directory of portable Bash files. There is no installer, no compiler, no runtime daemon. Copy the directory to the target server (or a Git clone) and invoke `bootstrap.sh`.

## Requirements

- Bash ≥ 5.0 (Ubuntu 24.04 ships 5.2; Debian 12 ships 5.2)
- `apt` (provided by the target OS)
- `systemctl` (provided by the target OS, which uses systemd)
- `sshd`, `sshd -t` (provided by the target OS)
- Root or `sudo` for stages 1+ (modules are explicit about requirements)
- Outbound HTTPS to distro mirrors and configured package sources

## Bootstrap a fresh server

### 1. Initial root connection

```bash
ssh root@your-new-server
```

The very first run begins with root because the bootstrap needs to create the admin user.

### 2. Install BootstrapX

```bash
git clone https://github.com/OWNER/bootstrapx.git /opt/bootstrapx
cd /opt/bootstrapx
cp examples/bootstrap.conf.example bootstrap.conf
$EDITOR bootstrap.conf
```

At minimum, set in `bootstrap.conf`:

- `HOSTNAME` — desired hostname
- `TIMEZONE` — IANA name (e.g. `Europe/Berlin`)
- `LOCALE` — e.g. `en_US.UTF-8`
- `ADMIN_USER` — the user you will SSH as after stage 1 (e.g. `admin`)
- `SSH_PUBLIC_KEYS` — one key per line; this key authenticates the admin user

### 3. First run — safe bootstrap

```bash
sudo ./bootstrap.sh --safe
```

`--safe` is the default. The runner:

1. Runs **Stage 0 — Preflight** (distro, arch, root, network, DNS, disk, memory).
2. Runs **Stage 1 — Safe Bootstrap**: updates apt, installs base packages, creates the admin user, installs SSH keys, configures sudo. **Root login stays enabled.** SSH config is validated with `sshd -t` before any reload.
3. Prompts you to reconnect as the admin user. Do not skip this step.

### 4. Reconnect and continue

In a **second terminal**:

```bash
ssh admin@your-new-server
cd /opt/bootstrapx
sudo ./bootstrap.sh --safe
```

This run re-enters the runner. Because root login is still enabled, the validator confirms the admin user can log in successfully. Only then does stage 2 (security hardening) lock root out.

### Optional network access

- Tailscale is enabled by default.
- For unattended enrollment, set `TAILSCALE_AUTH_KEY` in `bootstrap.conf`.
- If you do not want Tailscale on a host, set `ENABLE_TAILSCALE=false`.
- `ENABLE_PIGEONS=true` installs the optional Pigeons roost service on the server.

### 5. Validate

```bash
sudo ./bootstrap.sh doctor
```

Produces a human-readable and a machine-readable report (`state/doctor.json`).

## Upgrades

Re-running `./bootstrap.sh --safe` is the upgrade path. Each module's `check()` decides whether anything needs to change; untouched state is left alone.

## Dry-run

```bash
sudo ./bootstrap.sh --dry-run --verbose
```

Prints every action it would take without touching anything.

## Unattended

```bash
sudo ./bootstrap.sh --non-interactive --safe
```

Required for CI / cloud-init. Prompts are skipped; the run aborts on any unexpected decision.

## Removal

BootstrapX writes nothing outside its own directory except via the modules. To uninstall:

```bash
sudo /opt/bootstrapx/bootstrap.sh rollback
```

That restores every file that BootstrapX changed, in reverse order. To delete the framework afterwards, simply `rm -rf /opt/bootstrapx`.

## CI install (for testing)

```bash
sudo apt-get update
sudo apt-get install -y shellcheck shfmt bats
make ci    # or: shellcheck bootstrap.sh lib/*.sh modules/*.sh; shfmt -d .; bats tests/
```