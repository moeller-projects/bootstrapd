# Troubleshooting

## Symptom: `bootstrap.sh: command not found`

The script is not executable, or you ran it from outside its directory.

```bash
chmod +x bootstrap.sh
./bootstrap.sh --version
```

## Symptom: `must be run as root`

BootstrapX needs root for stage 1+. Use `sudo`:

```bash
sudo ./bootstrap.sh --safe
```

The `--safe` flag is the default; passing it explicitly is documentation.

## Symptom: `sshd: configuration invalid`

`ensure_line` applied a setting that `sshd -t` rejected. The framework refuses to restart sshd in that case, so the running sshd is unchanged. Inspect:

```bash
sudo sshd -t
sudo cat /etc/ssh/sshd_config
```

Edit the offending line directly, then re-run `./bootstrap.sh --safe`. The framework will detect the corrected value and skip the change.

## Symptom: lockout after stage 2

You should not see this in normal operation. If you do:

1. Use the cloud provider's console (Hetzner, DigitalOcean, AWS, etc.) to attach a serial console or mount the volume on another VM.
2. Edit `/etc/ssh/sshd_config`: set `PermitRootLogin yes` and `PasswordAuthentication yes`.
3. Restart sshd: `systemctl restart ssh`.
4. From your laptop, `ssh root@server` (the provider console usually lets you set an emergency root password).
5. Re-run `./bootstrap.sh doctor` to see what state is recorded.
6. Re-run `./bootstrap.sh --safe`.

## Symptom: `state/X.state: corrupt`

The state file is plain text. Inspect:

```bash
cat state/20-users.state
```

If `status=awaiting_admin_validation` is stuck after a successful reconnect, you confirmed the wrong terminal. Reconnect explicitly as the admin user, then run `./bootstrap.sh --safe`. The runner reads `state/20-users.state` and clears the flag.

## Symptom: `module not found: 99-foo`

You added a module file but forgot the `.sh` extension, or the prefix is not two digits. The loader only accepts `NN-name.sh`. Run:

```bash
ls modules/
```

## Symptom: `dependency cycle`

Two modules list each other in `dependencies()`. The runner refuses to continue. Fix one of them — typically a peer dependency is wrong.

## Symptom: `apt: package not found`

The package name changed, or the apt index is stale. Run:

```bash
sudo apt-get update
apt-cache search <name>
```

Update the module to use the correct package name, or add a `ppa:...` repo via `ensure_repo`.

## Symptom: `gpg: keyserver receive failed`

The default keyserver is unreachable. Override with `ensure_gpg_key --keyserver hkps://keys.openpgp.org URL FILE`.

## Symptom: `bootstrap doctor` reports `sshd: NOT REACHABLE`

`doctor` probes `sshd` on the configured port. If you changed `SSH_PORT`, the new value is in `bootstrap.conf`. Confirm the local firewall allows it:

```bash
sudo ufw status
ss -ltn | grep :<SSH_PORT>
```

## Symptom: I want to undo everything

```bash
sudo ./bootstrap.sh rollback
```

Restores every backed-up file in reverse order. Does not remove users or packages — those are tracked per-module.

## Getting logs

- Live log: `tail -F state/bootstrap.log`
- Last run summary: `cat state/last-run.json`
- Doctor report: `cat state/doctor.json`
- Per-module state: `ls state/*.state`

## Getting help

Open an issue: <https://github.com/OWNER/bootstrapx/issues>. Include the output of:

```bash
sudo ./bootstrap.sh --version
sudo ./bootstrap.sh doctor --json > /tmp/doctor.json
tail -200 state/bootstrap.log
```