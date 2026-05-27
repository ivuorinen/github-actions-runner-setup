# Rule: every shell script uses `set -Eeuo pipefail`

Every `.sh` file in this repository (entrypoint, healthcheck, hooks) starts
with:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
```

## Why each flag is required

- `-E` — `ERR` trap is inherited by shell functions and subshells. Without it,
  a failure inside `cleanup()` or `deregister_runner()` would not propagate.
- `-e` — exit immediately on a non-zero status, except in conditionals
  (`if`, `&&`, `||`). Prevents partial-failure flows from continuing.
- `-u` — treat unset variables as an error. Catches typos like
  `${GITHUB_APP_INSTAL_ID}` at run time. Required because the script
  references many env vars whose absence is fatal.
- `-o pipefail` — the exit status of a pipeline is the status of the last
  command to fail, not just the final stage. Without it, `cat broken | grep x`
  succeeds even if `cat` failed. The token parsing pipelines depend on this.

## Exceptions

- `set +e` inside `cleanup()` is intentional: cleanup must continue past
  individual failures (e.g. a `deregister_runner` call that errors must not
  abort the rest of the cleanup).
- `|| true` after a specific command is acceptable when that command is
  known to fail in normal operation (e.g. `kill -0 "${pid}" 2>/dev/null || true`).

## How to verify

```bash
shellcheck scripts/entrypoint.sh scripts/healthcheck.sh .claude/hooks/*.sh
shfmt -d scripts/entrypoint.sh scripts/healthcheck.sh
```

Both must produce no output.

Pre-commit enforces shellcheck and shfmt; see `.pre-commit-config.yaml`.
