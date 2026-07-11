# Module Development

A BootstrapX module is one Bash file under `modules/`. The runner discovers it, sources it once, and calls its functions in a fixed protocol.

## File name

```
modules/NN-name.sh
```

- `NN` — load-order prefix. Two digits, zero-padded. The runner sorts modules by `NN` first, then by dependency graph.
- `name` — kebab-case short name.

The prefix is **not** authoritative for ordering; `dependencies()` is. The prefix exists so an operator looking at `ls modules/` sees the intended order.

## Required functions

Every module must define these functions. Their names start with `mod_<NN>_` so the runner can dispatch via shell parameter expansion without parsing.

```bash
mod_NN_description()  { echo "Short description of what this module does"; }
mod_NN_stage()        { echo "1"; }                      # 0..7
mod_NN_dependencies() { echo "10-base"; }               # space-separated module IDs
mod_NN_check()        { ... return 0; }                  # 0 = already done; 1 = needs work
mod_NN_install()      { ... }                           # apply changes (idempotent)
mod_NN_validate()     { ... return 0; }                  # post-install sanity check
mod_NN_rollback()     { ... }                           # undo install()
```

`NN` here is the literal two-digit prefix of the module. The runner builds the function name from the file name.

### `check()` semantics

- Return `0` if the module's desired state is already present.
- Return `1` if `install()` needs to run.
- Return `2` if the user passed `--force` and wants a re-run regardless. Honour `--force` by reading `$BOOTSTRAP_FORCE`.

`check()` must be **fast and read-only**. No file mutations, no service restarts, no package installs. The runner calls `check()` every time, including in `--dry-run`.

### `install()` semantics

- Always go through `ensure_*` helpers. Never call `apt`, `systemctl`, `useradd`, `cp`, `mv`, or `echo >>` directly.
- If you must back up a file before editing, call `backup_file PATH` and `register_rollback PATH BACKUP`. The framework's rollback will replay those.
- Wrap risky operations in `with_rollback_on_failure ... || return 1`. The runner's trap will fire `rollback` automatically on failure.

### `validate()` semantics

- Return `0` if everything the module was supposed to do is verifiable post-install.
- Return non-zero on any anomaly. The runner treats a non-zero return as a failure and rolls the module back.
- Do not make `validate()` interactive.

### `rollback()` semantics

- Restore every backup registered with `register_rollback` and remove any state the module created (files outside `state/`, users, packages).
- Be tolerant: if the rollback target is already gone, do not error.
- Run in reverse order if there are multiple steps.

## Choosing helpers

| Want to | Use |
|---|---|
| Install an apt package | `ensure_package curl` |
| Install many apt packages | `ensure_packages "curl git jq"` |
| Add an apt repo | `ensure_repo "deb [signed-by=/etc/apt/keyrings/docker.gpg] https://..." docker` |
| Add a GPG key | `ensure_gpg_key URL FILE` |
| Create a user | `ensure_user alice` |
| Create a group | `ensure_group docker` |
| Create a directory | `ensure_directory /opt/foo mode 0755 owner user:group` |
| Write a static file | `ensure_file /etc/foo.conf "..."` |
| Render a template | `ensure_template /etc/foo.conf templates/foo.tpl` |
| Patch a line in a file | `ensure_line /etc/sshd_config "PermitRootLogin no"` |
| Patch a block | `ensure_block FILE MARKER TEXT` |
| Create or refresh a symlink | `ensure_symlink /usr/local/bin/foo /opt/foo/bin/foo` |
| Fix permissions | `ensure_permission /etc/foo mode 0644 owner root:root` |
| Enable a service | `ensure_service_enabled ssh` |
| Disable a service | `ensure_service_disabled telnet` |
| Start a service | `ensure_service_running ssh` |
| Apply a sysctl | `ensure_sysctl net.ipv4.ip_forward 1` |
| Set hostname | `ensure_hostname myhost` |
| Set timezone | `ensure_timezone Europe/Berlin` |
| Install a cron job | `ensure_cron "0 5 * * * /usr/local/bin/foo"` |
| Install a systemd timer | `ensure_timer` (see source) |
| Set an env var globally | `ensure_environment_variable NAME VALUE` |

If no helper fits, add a new one to `lib/ensure.sh` rather than reaching for raw `apt` or `systemctl`. The framework's quality comes from this discipline.

## Example: a complete module

```bash
#!/usr/bin/env bash
# modules/45-caddy.sh — install Caddy as a systemd service
set -Eeuo pipefail

mod_45_description() { echo "Install and enable Caddy reverse proxy"; }
mod_45_stage()       { echo "3"; }
mod_45_dependencies(){ echo "10-base 30-security"; }

mod_45_check() {
  command -v caddy >/dev/null && return 0
  return 1
}

mod_45_install() {
  ensure_packages "caddy" || return 1
  ensure_service_enabled caddy
  ensure_service_running caddy
}

mod_45_validate() {
  systemctl is-active --quiet caddy
}

mod_45_rollback() {
  systemctl disable --now caddy 2>/dev/null || true
  apt-get -y purge caddy 2>/dev/null || true
}
```

## Tests

Every module ships with a Bats test under `tests/modules/NN-name.bats` that exercises:

- `check()` returns 0 after a successful install.
- A second install is a no-op (idempotency).
- `validate()` returns 0.
- `rollback()` restores the pre-install state.

See `tests/modules/20-users.bats` for a worked example.

## Style

- `set -Eeuo pipefail` at the top.
- All functions `local`-scope their variables.
- Quote every expansion.
- No `cd` without `pushd`/`popd` or a final absolute path.
- No command substitution in `[[ ]]` without the `-n`/`-z` style.
- Run `shellcheck modules/*.sh` and `shfmt -d modules/*.sh` before committing.

## Adding a new `ensure_*` helper

If your module needs a helper that does not exist, add it to `lib/ensure.sh`. The convention is:

```bash
ensure_thing() {
  local thing="$1"
  if [[ "$(current_thing)" == "$thing" ]]; then
    log_debug "thing already $thing"
    return 0
  fi
  if (( BOOTSTRAP_DRY_RUN )); then
    log_info "would set thing to $thing"
    return 0
  fi
  do_set_thing "$thing"
  register_rollback "thing" "do_unset_thing"
  log_success "thing set to $thing"
}
```

Add a unit test under `tests/ensure.bats`. Run the full suite with `bats tests/`.