# Security

## Threat model

BootstrapX is invoked as root on a server whose admin endpoint is initially `ssh root@server`. The threat is straightforward: every step that touches authentication or network exposure is a candidate for locking the operator out of their own machine.

The framework's defenses:

1. **`sshd -t` before any restart.** Any change to `/etc/ssh/sshd_config` is validated by running `sshd -t`. A non-zero exit aborts the change before the service is reloaded.
2. **Staged lockout prevention.** Stage 1 ends with root login still enabled. Stage 2 only disables root after the runner has confirmed the admin user exists, has an `authorized_keys`, has correct permissions, has working sudo, and (best effort) has logged in successfully.
3. **Defensive sudoers.** The admin user gets passwordless sudo only from the admin group, only with a timestamp timeout (default 15 minutes), only via a fully-qualified `/etc/sudoers.d/admin` snippet that sudoers parses cleanly.
4. **Backup-then-mutate.** Every file change goes through `backup_file` and `register_rollback` before the write happens. A failed write rolls back.
5. **`--safe` is the default.** `--force` must be passed explicitly to skip the safety prompts; even with `--force`, the SSH and root-login gates still apply.
6. **Dry-run.** `--dry-run` is a hard read-only path — no `install()` ever mutates state in dry-run mode.

## Safe bootstrap flow

```
initial state: root@server login works via password OR existing key

stage 1:
  1. apt update && apt upgrade
  2. install base packages (sudo, openssh-server, ca-certificates, curl, gnupg, lsb-release)
  3. ensure admin user exists with UID >= 1000
  4. ensure /home/<admin>/.ssh/ exists, mode 0700
  5. install ADMIN_USER's SSH_PUBLIC_KEYS into authorized_keys, mode 0600
  6. create /etc/sudoers.d/<admin> with passwordless sudo
  7. validate: sshd -t
  8. reload sshd
  9. record state/20-users.state with status=awaiting_admin_validation

THE RUNNER PROMPTS THE OPERATOR:

  >>> Reconnect as the admin user in a NEW terminal before continuing.
      ssh <ADMIN_USER>@server
      cd <bootstrap dir>
      sudo ./bootstrap.sh --safe
      Press Enter ONLY AFTER you have successfully logged in.

stage 2 (next run):
  10. verify state/20-users.state exists and admin user is authenticatable
  11. optionally install/enroll Tailscale and/or Pigeons if enabled
  12. write /etc/ssh/sshd_config:
        PermitRootLogin no
        PasswordAuthentication no
        PubkeyAuthentication yes
  13. sshd -t (must succeed)
  14. reload sshd
```

If the operator does **not** confirm in step 9 and runs `--force` instead, the runner refuses: it will not disable root login without the awaiting_admin_validation state having been cleared by a successful reconnect.

## SSH hardening baseline

Hardening applied in stage 2 by default:

```
Port <SSH_PORT>
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
X11Forwarding no
AllowAgentForwarding yes
AllowTcpForwarding yes
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
```

The framework writes these values through `ensure_line` so an operator who customizes any line is preserved across re-runs.

## Reporting a vulnerability

Open a private security advisory on GitHub: <https://github.com/OWNER/bootstrapx/security/advisories/new>. Do not file a public issue.