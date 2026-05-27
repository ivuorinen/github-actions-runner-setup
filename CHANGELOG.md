# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `docs/audit/nitpicker-findings.md` — adversarial audit findings, regenerated
  by the nitpicker skill across iterative passes.
- `docs/ARCHITECTURE.md`, `docs/OPERATIONS.md`, `docs/TROUBLESHOOTING.md`,
  `docs/ENVIRONMENT-VARIABLES.md`, `docs/SECURITY.md` — comprehensive operator
  documentation.
- `.claude/rules/` — 11 invariant files documenting architectural and security
  constraints that future changes must respect.
- `.claude/hooks/` — additional PreToolUse/PostToolUse hooks for docker.sock
  containment, base-image digest pinning, shell strict-mode enforcement,
  token-logging detection, `cat .env` / `cat *.pem` blocking, hadolint
  invocation, and bash arithmetic precedence verification.
- `scripts/pre-commit-hooks/` — local pre-commit hooks shared between
  pre-commit runs and CI for arithmetic-precedence and docker-sock-in-runner
  checks.
- `Makefile` for day-to-day developer commands.
- `CONTRIBUTING.md`, `SECURITY.md` (root) — contribution flow and security
  disclosure policy.
- `SECURITY.md` (`docs/`) — full threat model and defensive choices.
- GHES (GitHub Enterprise Server) support: setting `GITHUB_HOST` now derives
  the API and web URLs automatically; explicit `GITHUB_API_URL`/`GITHUB_WEB_URL`
  override the derivation.
- Pending-signal queue in `entrypoint.sh` to handle SIGTERM arriving before
  `runner_pid` is assigned, preventing orphaned runner listeners.
- Tightened healthcheck to anchor on `/home/runner/run.sh` and
  `Runner.Listener` (no false positives on workflow scripts named `run.sh`).
- Token-length sanity check (`>= 10 chars`) in `extract_token()` to defend
  against `{"token":""}` API responses.
- HTTP_PROXY / IPv6 / DNS notes in `docs/OPERATIONS.md`.
- Socket-proxy healthcheck, read-only root filesystem, resource limits,
  log rotation, and `LOG_LEVEL: warning`.
- Runner-service `depends_on socket-proxy: service_healthy`,
  `stop_grace_period: 2m`, `ulimits: nofile`, log rotation.
- OCI image labels (title, description, source, documentation, licenses,
  vendor, base.name) on the runner image.
- CI smoke test that boots the image with a mode-644 PEM and asserts the
  entrypoint rejects it.
- CI regression checks for the bash arithmetic precedence pattern and for
  docker.sock mounted outside `socket-proxy`.

### Fixed

- **Critical:** bash arithmetic operator precedence in the PEM mode check in
  `scripts/entrypoint.sh` — `(((8#${key_mode}) & 077 == 0))` parses as
  `key & (077 == 0)` = `key & 0` = `0`, making the check fail for every
  mode (including the required `0600`). Container could not start with any
  PEM configuration. Fixed by parenthesising the bitwise expression:
  `((((8#${key_mode}) & 077) == 0))`. Encoded as rule 09 with grep guards
  in pre-commit + CI to prevent regression.
- Adversarial bypasses in `.claude/hooks/block-cat-secrets.sh`:
  `bash -c "cat .env"`, `cat '.env'`, `cat ".env"` previously slipped
  through; now normalised and detected.
- `.claude/hooks/block-runner-socket-mount.sh` long-form `source:` volume
  syntax bypass.
- `.editorconfig` did not cover `Makefile` (capital M); also aligned YAML
  max line length with `markdownlint`.
- `.gitignore` `.env.*` pattern was ignoring `.env.example`; added explicit
  negation.
- `extract_token()` accepted `{"token":""}`; now requires >=10 chars.
- `api()` tempfile cleanup converted to `RETURN` trap (signal-safe).
- `.claude/settings.json` hook commands now use `${CLAUDE_PROJECT_DIR}` to
  resolve regardless of Claude's current working directory.

### Changed

- Pre-commit `shellcheck` severity from `style` (verified) and explicit
  hook re-ordering (formatter shfmt before linter shellcheck).
- Curl request timeout `--max-time` increased from 30 to 60 seconds per
  attempt to tolerate slow API responses without spurious retries.
- Healthcheck `start-period` increased from 30s to 60s; `retries` from 3
  to 5 to give cold-start token-exchange enough time on slow networks.

[Unreleased]: https://github.com/ivuorinen/github-actions-runner-setup/compare/main...HEAD
