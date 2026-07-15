# Configuration

Every tunable lives in `bootstrap.conf`. The file is a `KEY=value` sourceable shell snippet; comments start with `#`. Nothing else is read from disk at runtime.

A working example is at [`examples/bootstrap.conf.example`](examples/bootstrap.conf.example).

## Identity

| Key | Type | Default | Description |
|---|---|---|---|
| `HOSTNAME` | string | — | Desired hostname. Applied with `hostnamectl set-hostname`. |
| `TIMEZONE` | IANA name | `UTC` | e.g. `Europe/Berlin`. Linked into `/etc/localtime`. |
| `LOCALE` | locale name | `en_US.UTF-8` | Generated with `locale-gen`. |
| `ADMIN_USER` | username | `admin` | First non-root user. Created in stage 1. |
| `DEPLOY_USER` | username | `deploy` | Used by CI/CD. Optional. |
| `AGENT_USER` | username | `agent` | Used by AI agents. Optional. |

## Network

| Key | Type | Default | Description |
|---|---|---|---|
| `SSH_PORT` | port | `22` | Listening port for sshd. Validated before reload. |
| `SSH_PUBLIC_KEYS` | multi-line | — | One key per line. Installed for every user with SSH access. |
| `ENABLE_TAILSCALE` | bool | `true` | Install and enroll Tailscale. |
| `TAILSCALE_AUTH_KEY` | string | — | Optional auth key for unattended Tailscale enrollment. |
| `ENABLE_PIGEONS` | bool | `false` | Install the optional Pigeons SSH-over-QUIC service. |
## Packages

| Key | Type | Default | Description |
|---|---|---|---|
| `ENABLE_PODMAN` | bool | `true` | Install Podman, buildah, skopeo, configure rootless. |
| `ENABLE_DOCKER` | bool | `false` | Install Docker CE. Podman remains the default. |
| `ENABLE_GITHUB_CLI` | bool | `true` | Install `gh`. |
| `NODE_VERSION` | major | `22` | Node.js LTS major version. |
| `DOTNET_CHANNEL` | string | `9.0` | .NET SDK channel. |
| `PYTHON_VERSION` | major.minor | `3.12` | Default Python. |

## AI tooling

| Key | Type | Default | Description |
|---|---|---|---|
| `ENABLE_OPENCLAW` | bool | `true` | Install OpenClaw. |
| `ENABLE_PI` | bool | `true` | Install Pi Coding Agent. |
| `ENABLE_CODEX` | bool | `true` | Install Codex CLI. |
| `ENABLE_CLAUDE` | bool | `true` | Install Claude Code. |
| `ENABLE_OLLAMA` | bool | `false` | Install Ollama. |

## Security

| Key | Type | Default | Description |
|---|---|---|---|
| `ENABLE_FAIL2BAN` | bool | `true` | Install and enable fail2ban. |
| `ENABLE_APPARMOR` | bool | `true` | Enable AppArmor profiles. |
| `ENABLE_AUTO_UPDATES` | bool | `true` | `unattended-upgrades` for security patches. |
| `ENABLE_MONITORING` | bool | `true` | btop, smartmontools, vnstat, etc. |
| `ENABLE_CADDY` | bool | `false` | Install Caddy. |

## Podman

| Key | Type | Default | Description |
|---|---|---|---|
| `PODMAN_STORAGE` | path | `/var/lib/containers/storage` | Rootless storage root. |
| `PODMAN_REGISTRIES` | list | `docker.io quay.io ghcr.io` | Registries search path. |

## Validation pattern

`bootstrap.conf` is loaded once at startup and validated against a schema in `lib/config.sh`. Unknown keys are warned about (in `--verbose`) but do not abort — useful for forward compatibility. Empty values fall back to defaults declared in the schema.

## Reloading

There is no hot-reload. Edit `bootstrap.conf`, re-run `./bootstrap.sh`. Idempotent: only modules whose configuration actually changed will touch anything.