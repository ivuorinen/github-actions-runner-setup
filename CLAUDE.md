# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Ephemeral GitHub Actions self-hosted runner system using GitHub App authentication,
deployed via Docker Compose. Designed for Coolify but works standalone.
Each runner registers, executes one job, exits, and Docker restarts it fresh.

## Architecture

**Auth flow:** GitHub App JWT (9-min expiry) → Installation Token → Registration Token → Ephemeral Runner → Auto-deregister on exit.

- `scripts/entrypoint.sh` — Orchestrates the entire lifecycle: JWT creation, token exchange, runner config, cleanup trap for deregistration
- `scripts/healthcheck.sh` — Simple process check for Docker HEALTHCHECK
- `Dockerfile` — Extends `ghcr.io/actions/actions-runner`, adds curl/jq/openssl/git/docker/tini
- `docker-compose.yml` — 3 runner services using YAML anchor (`&runner-common`); per-service `environment:` blocks (YAML merge doesn't deep-merge, so the anchor's environment is intentionally omitted)
- `.env.example` — Full configuration reference with all supported variables

**Key design decisions:**

- YAML merge (`<<: *anchor`) doesn't deep-merge `environment:` keys — each service must declare its own complete environment block
- `env_file` uses `required: false` (Compose v2.24+) for Coolify compatibility where env vars are injected directly
- Runner deregistration happens in a subshell inside the cleanup trap so `fail()` calls don't abort PEM cleanup

## Linting and Validation

```bash
# Shell scripts
shellcheck scripts/entrypoint.sh
shfmt -d scripts/entrypoint.sh

# YAML
yamllint docker-compose.yml

# All pre-commit hooks at once
pre-commit run --all-files
```

Pre-commit hooks enforce: shellcheck, shfmt, yamllint, markdownlint, actionlint, checkov, detect-private-key.

## Code Style

- 2-space indentation (4-space tabs for Makefiles)
- UTF-8, LF line endings
- Max 200 chars for YAML/Markdown; 160 chars general
- Shell scripts: `set -Eeuo pipefail`, functions use `local` for all variables
- ShellCheck directive SC2129 is disabled (`.shellcheckrc`)
