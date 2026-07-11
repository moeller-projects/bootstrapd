.PHONY: help lint shellcheck shfmt bats test ci clean

SHELL := /usr/bin/env bash

SH_FILES := bootstrap.sh \
  $(wildcard lib/*.sh) \
  $(wildcard modules/*.sh) \
  $(wildcard tests/*.sh)

help:
	@echo 'BootstrapX targets:'
	@echo '  make shellcheck  - run shellcheck on all *.sh files'
	@echo '  make shfmt        - check formatting with shfmt'
	@echo '  make fmt          - apply shfmt formatting'
	@echo '  make bats         - run bats test suites'
	@echo '  make test         - run shellcheck + shfmt + bats'
	@echo '  make doctor       - run bootstrap doctor locally'

shellcheck:
	@command -v shellcheck >/dev/null || { echo 'shellcheck not installed'; exit 1; }
	shellcheck --severity=warning --shell=bash $(SH_FILES)

shfmt:
	@command -v shfmt >/dev/null || { echo 'shfmt not installed'; exit 1; }
	shfmt -d -i 2 -ci -fn $(SH_FILES)

fmt:
	@command -v shfmt >/dev/null || { echo 'shfmt not installed'; exit 1; }
	shfmt -w -i 2 -ci -fn $(SH_FILES)

bats:
	@command -v bats >/dev/null || { echo 'bats not installed'; exit 1; }
	bats tests/

test: shellcheck shfmt bats
	@echo "all checks passed"

doctor:
	@sudo ./bootstrap.sh doctor || true

ci: test
	@echo "CI complete"