# Rule: YAML anchor merge (`<<: *anchor`) does NOT deep-merge `environment:`

`docker-compose.yml` uses `x-runner-common: &runner-common` as a YAML anchor
to share configuration across `runner-1`, `runner-2`, `runner-3`. Each
runner service merges the anchor via `<<: *runner-common`.

**YAML merge replaces keys, it does not deep-merge them.** If both the anchor
and the service define `environment:`, the service's block REPLACES the
anchor's block entirely — no key-by-key merge happens.

## Why this matters here

The anchor intentionally **does not** define an `environment:` block. Each
runner service declares its complete environment in its own block. If you
added shared env vars to the anchor, they would be silently dropped from any
service that also has an `environment:` block (which is all of them).

## What to do instead

If you need a shared env var across all runners, either:

1. Put it in `.env` and reference it from each service's `environment:`
   block via `${VARNAME:-default}`. This is the current pattern.
2. Add it to every runner service's `environment:` block, copy-pasted.
3. Move it to a single `RUNNER_*` variable read in `entrypoint.sh` from
   the per-service env.

## What this rule forbids

```yaml
x-runner-common: &runner-common
  environment:                # forbidden in this repo
    DOCKER_HOST: tcp://...    # will be silently dropped by services using <<:
```

## Verification

```bash
docker compose config | grep -A3 'environment:'
```

Every runner service's env block must show all required keys
(`GITHUB_APP_ID`, `RUNNER_SCOPE`, etc.). If a key is missing from a service,
the anchor/service merge is wrong.

This is documented in `CLAUDE.md` under "Key design decisions".
