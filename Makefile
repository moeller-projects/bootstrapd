.PHONY: help lint test bats ci doctor release clean

SHELL := /usr/bin/env bash

help:
	@echo 'BootstrapX targets:'
	@echo '  make lint      - run pipelines/lint.sh (shellcheck + shfmt)'
	@echo '  make test      - run pipelines/test.sh (bats)'
	@echo '  make doctor    - run pipelines/doctor.sh'
	@echo '  make release   - build a versioned tarball via pipelines/release.sh'
	@echo '  make ci        - run the full pipeline (everything)'
	@echo '  make clean     - remove state logs and tmp files'

lint:
	./pipelines/lint.sh

test:
	./pipelines/test.sh

doctor:
	sudo ./pipelines/doctor.sh || ./pipelines/doctor.sh

release:
	./pipelines/release.sh release

ci: lint test doctor
	./pipelines/lint-docs.sh
	./pipelines/lint-yml.sh

clean:
	./bootstrap.sh clean
