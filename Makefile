# Makefile for the ephemeral GitHub Actions runner setup.
# Targets are thin wrappers around the docker compose / pre-commit / lint
# commands the contributor docs reference. See CONTRIBUTING.md.
#
# Style: tabs for recipes (POSIX make requirement), targets ordered by
# expected developer use (top → bottom = day-to-day → release).

SHELL := /usr/bin/env bash
.SHELLFLAGS := -Eeuo pipefail -c
.ONESHELL:
.DEFAULT_GOAL := help

COMPOSE ?= docker compose
PRECOMMIT ?= pre-commit

.PHONY: help
help:  ## Show this help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# -- Lint and verification ---------------------------------------------------

.PHONY: install-hooks
install-hooks:  ## Install pre-commit git hooks into .git/hooks.
	$(PRECOMMIT) install

.PHONY: lint
lint:  ## Run every pre-commit hook against every file.
	$(PRECOMMIT) run --all-files

.PHONY: lint-shell
lint-shell:  ## Shellcheck + shfmt diff against scripts/ and .claude/hooks/.
	shellcheck scripts/*.sh .claude/hooks/*.sh
	shfmt -d scripts/*.sh .claude/hooks/*.sh

.PHONY: lint-yaml
lint-yaml:  ## yamllint against docker-compose and CI workflows.
	yamllint docker-compose.yml .github/workflows/*.yml .pre-commit-config.yaml .yamllint.yml .mega-linter.yml

.PHONY: lint-docker
lint-docker:  ## hadolint against the Dockerfile (uses the pinned container).
	docker run --rm -i \
	  hadolint/hadolint:v2.12.0@sha256:7dba9a9f1a0350f6d021fb2f6f88900998a4fb0aaf8e4330aa8c38544f04db42 \
	  hadolint - <Dockerfile

.PHONY: lint-compose
lint-compose:  ## Validate docker-compose.yml resolves without errors.
	$(COMPOSE) config --quiet

# -- Build and lifecycle -----------------------------------------------------

.PHONY: build
build:  ## Build the runner image with the latest base layer.
	$(COMPOSE) build --pull

.PHONY: up
up:  ## Start the runner fleet detached.
	$(COMPOSE) up -d

.PHONY: down
down:  ## Stop and remove the runner fleet (preserves images).
	$(COMPOSE) down

.PHONY: restart
restart:  ## Restart all services in place.
	$(COMPOSE) restart

.PHONY: logs
logs:  ## Tail logs from all services.
	$(COMPOSE) logs --since 5m -f

.PHONY: logs-runner-1
logs-runner-1:  ## Tail logs from runner-1.
	$(COMPOSE) logs --since 5m -f runner-1

.PHONY: ps
ps:  ## Show the state of every service.
	$(COMPOSE) ps

.PHONY: shell
shell:  ## Open an interactive shell in runner-1 as the runner user.
	$(COMPOSE) exec --user runner runner-1 bash

# -- Security / audit --------------------------------------------------------

.PHONY: audit
audit:  ## Run checkov + trivy against the repo and the built image.
	$(PRECOMMIT) run checkov --all-files
	@command -v trivy >/dev/null 2>&1 && trivy fs --severity HIGH,CRITICAL . || echo "trivy not installed; skipping"

.PHONY: audit-image
audit-image:  ## Trivy scan against the built runner image.
	@command -v trivy >/dev/null 2>&1 || { echo "trivy is required"; exit 1; }
	trivy image --severity HIGH,CRITICAL $${RUNNER_IMAGE_NAME:-local/github-app-actions-runner:latest}

# -- Maintenance -------------------------------------------------------------

.PHONY: pull
pull:  ## Pull the socket-proxy image (the runner image is built locally).
	$(COMPOSE) pull socket-proxy

.PHONY: clean
clean:  ## Remove the local runner image to force a fresh build.
	docker image rm -f $${RUNNER_IMAGE_NAME:-local/github-app-actions-runner:latest} 2>/dev/null || true

.PHONY: prune
prune:  ## Prune unused images and build cache on the host (interactive).
	docker image prune
	docker builder prune
