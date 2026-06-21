# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Ephemeral GitHub Actions self-hosted runner system using GitHub App authentication,
deployed via Docker Compose. Designed for Coolify but works standalone.
Each runner registers, executes one job, exits, and Docker restarts it fresh.

For full architecture see `docs/ARCHITECTURE.md`. For operations see `docs/OPERATIONS.md`.

## Architecture

**Auth flow:** GitHub App JWT (9-min expiry) → Installation Token → Registration Token → Ephemeral Runner → Auto-deregister on exit.

- `scripts/entrypoint.sh` — Orchestrates the entire lifecycle: JWT creation, token exchange, runner config, cleanup trap for deregistration
- `scripts/healthcheck.sh` — Simple process check for Docker HEALTHCHECK
- `scripts/pre-commit-hooks/` — Local pre-commit hook scripts (arithmetic-precedence check, no-docker-sock-in-runner check)
- `Dockerfile` — Extends `ghcr.io/actions/actions-runner`, adds curl/jq/openssl/git/docker/tini
- `docker-compose.yml` — 3 runner services using YAML anchor (`&runner-common`); per-service `environment:` blocks (YAML merge doesn't deep-merge, so the anchor's environment is intentionally omitted)
- `.env.example` — Full configuration reference with all supported variables (canonical reference in `docs/ENVIRONMENT-VARIABLES.md`)
- `.claude/rules/` — Invariants that must hold; read before modifying entrypoint, Dockerfile, or compose
- `.claude/hooks/` — PreToolUse/PostToolUse hooks enforcing those invariants client-side

**Key design decisions:**

- YAML merge (`<<: *anchor`) doesn't deep-merge `environment:` keys — each service must declare its own complete environment block. See `.claude/rules/05-yaml-anchor-no-env-merge.md`.
- `env_file` uses `required: false` (Compose v2.24+) for Coolify compatibility where env vars are injected directly.
- Runner deregistration happens in a subshell inside the cleanup trap so `fail()` calls don't abort PEM cleanup. See `.claude/rules/07-cleanup-trap-isolation.md`.
- Bash arithmetic with bitwise + comparison must be parenthesised: `((a & b) == c)` not `((a & b == c))`. See `.claude/rules/09-arithmetic-precedence-bash.md`.

## Linting and Validation

```bash
make lint                  # pre-commit run --all-files (recommended)
make lint-shell            # shellcheck + shfmt on scripts/ and .claude/hooks/
make lint-yaml             # yamllint on compose + CI workflows
make lint-docker           # hadolint via the pinned container
make lint-compose          # docker compose config --quiet
```

Pre-commit hooks enforce: shellcheck, shfmt, yamllint, markdownlint, actionlint,
checkov, hadolint, detect-private-key, and four local guards: arithmetic-precedence
trap, docker.sock-not-in-runner, security invariants for rules 06/11/12/13 +
`no-new-privileges`, and the `.claude/hooks` block/allow behavior test.

## Context efficiency

Use the **context-mode** plugin (`ctx_execute` / `ctx_execute_file` /
`ctx_fetch_and_index` + `ctx_search`) **by default** for anything that might
fill the context window — not only known-large outputs. The test is "could this
fill context?", and if the answer is yes or unsure (any command with
unpredictable output size, file analysis, web fetches, repo-wide search), keep
the raw bytes in the sandbox and let only a summary enter context. Raw
Bash/`Read` stays correct for certainly-tiny verbatim output, `Edit`/`Write`
mutations, and `Read`-before-`Edit`. The plugin is enabled in
`.claude/settings.json` and auto-routes via a `PreToolUse` hook.
See `.claude/rules/14-use-context-mode-by-default.md`.

## Code Style

- 2-space indentation (4-space tabs for Makefiles)
- UTF-8, LF line endings
- Max 200 chars for YAML/Markdown; 160 chars general
- Shell scripts: `set -Eeuo pipefail`, functions use `local` for all variables
- ShellCheck directive SC2129 is disabled (`.shellcheckrc`)

## Where to read next

- `docs/ARCHITECTURE.md` — system design, container lifecycle, token chain, privilege boundary
- `docs/OPERATIONS.md` — day-2 ops, scaling, credential rotation
- `docs/TROUBLESHOOTING.md` — common failures and fixes
- `docs/ENVIRONMENT-VARIABLES.md` — every env var read by the system
- `docs/SECURITY.md` — threat model and defensive choices
- `docs/SECURITY-REVIEW-2026-04-20.md` — formal security review findings
- `docs/audit/nitpicker-findings.md` — adversarial audit findings
- `.claude/rules/` — encoded invariants (read top to bottom before touching shell/compose/dockerfile)
