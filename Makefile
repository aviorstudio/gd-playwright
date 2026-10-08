SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
.NOTPARALLEL:
.PHONY: help install lint test build check dev stop clean
help:
	@echo 'make install: pinned tools and browser; make check: all shipped suites, exact ZIP, editor and web exports'
install:
	mise trust .mise.toml
	mise install go bun node python actionlint shellcheck http:cicd-engineering
	mise exec -- bash scripts/profile.sh install
lint test build:
	mise exec -- bash scripts/profile.sh $@
check: lint test build
	mise exec -- bash scripts/profile.sh artifact-check
dev stop:
	@echo '$@: unsupported: run the addon in its consuming Godot project'
clean:
	mise exec -- python3 -c 'import shutil; [shutil.rmtree(p, ignore_errors=True) for p in (".artifacts", "dist", ".godot", "tools/browser/node_modules", ".playwright-cli")]'
