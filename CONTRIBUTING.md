# Contributing

Thanks for taking an interest in BootstrapX. The framework is small on purpose; please keep it that way.

## Ground rules

- **Every Bash file starts with `#!/usr/bin/env bash` and `set -Eeuo pipefail`.**
- **No `apt`, `systemctl`, `useradd`, `groupadd`, `cp`, `mv`, `echo >>`** outside `lib/`. Everything routes through an `ensure_*` helper.
- **No placeholder code.** Either ship it or do not open the PR.
- **Tests come with the change.** New helper → new test in `tests/`. New module → new test in `tests/modules/`.
- **Documentation is part of the change.** New module → update `MODULE_DEVELOPMENT.md`. New config key → update `CONFIGURATION.md`.

## Local toolchain

```bash
sudo apt-get install -y shellcheck shfmt bats
```

CI installs the same; running them locally first catches most review noise.

## Style

The Bash code in this repo follows these conventions on top of standard ShellCheck guidance:

- `local` for every function variable.
- `[[ ]]` for tests, not `[ ]`.
- `printf` for data, `echo` for human-only output.
- `read -r`.
- Lower-case variable names for locals; `BOOTSTRAP_*` for globals.
- Two-space indentation, no tabs.
- Functions named `mod_<NN>_<verb>` for modules, `ensure_<verb>` for helpers.

shfmt config (`.editorconfig`):

```
root = true

[*.sh]
indent_style = space
indent_size = 2
end_of_line = lf
insert_final_newline = true
```

## Running tests

```bash
make test        # shellcheck + shfmt + bats
make shellcheck  # static analysis only
make bats        # unit tests only
```

## Commit messages

Imperative mood, 72-column subject, blank line, optional body.

```
modules: add 45-caddy module

Installs Caddy as a reverse proxy, enabled and started on boot.
```

Prefix with the area: `lib:`, `modules:`, `docs:`, `tests:`, `ci:`, `runner:`.

## Pull request flow

1. Fork, branch from `main`.
2. Make the change. Include tests.
3. `make test` must pass.
4. Open the PR against `main`. Fill the template. Reference any related issue.
5. CI must be green before review.

## Release flow

- `main` is always releasable.
- Version bumps land on `main` as a single commit titled `release: vX.Y.Z`.
- Tag is created from that commit; `CHANGELOG.md` is updated in the same commit.
- GitHub Actions publishes a release artifact (a tarball of the repo at the tagged commit).