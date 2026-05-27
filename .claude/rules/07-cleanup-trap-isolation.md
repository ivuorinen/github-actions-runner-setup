# Rule: cleanup handlers run each step in an isolated subshell

In `scripts/entrypoint.sh`, `cleanup()` is registered as an `EXIT` trap and
runs on normal exit, error exit, and after SIGTERM/SIGINT propagation. It
**must** isolate each side-effect so that one failure cannot prevent later
ones.

The pattern in use:

```bash
cleanup() {
  local exit_code="$?"
  set +e

  if [[ -f ".runner" ]]; then
    log 'Removing runner registration'
    (deregister_runner) || log 'Warning: failed to deregister runner'
  fi

  exit "${exit_code}"
}
```

## Why

- `local exit_code="$?"` captures the exit code at the moment of trap entry.
  Any commands run inside `cleanup` would otherwise overwrite `$?` and the
  script would exit with the wrong status.
- `set +e` disables the error-exit behaviour from `set -e` so that one
  failed cleanup step does not abort the function.
- `(deregister_runner)` runs in a subshell. Any `fail()`/`exit` inside the
  function terminates only the subshell, not the parent. Without the
  subshell, a `fail()` would skip the rest of cleanup — including the final
  `exit "${exit_code}"` — and lose the original exit status.

## What this rule forbids

```bash
cleanup() {
  deregister_runner   # forbidden — fail() inside aborts cleanup
  remove_pem
  exit
}

cleanup() {
  if ! deregister_runner; then       # forbidden under set -e
    log 'failed'
  fi
}
```

## Adding a new cleanup step

```bash
cleanup() {
  local exit_code="$?"
  set +e

  if [[ -f ".runner" ]]; then
    (deregister_runner) || log 'Warning: deregister failed'
  fi

  # New step goes here, same pattern:
  (new_cleanup_action) || log 'Warning: new action failed'

  exit "${exit_code}"
}
```

The hook `.claude/hooks/warn-entrypoint-token-handling.sh` flags edits to
this region.
