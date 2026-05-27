# Rule: runner containers never mount `/var/run/docker.sock`

Only the `socket-proxy` service in `docker-compose.yml` is allowed to bind
`/var/run/docker.sock` from the host. Runner containers (`runner-1`,
`runner-2`, …) must reach Docker via `DOCKER_HOST=tcp://socket-proxy:2375`.

## Why

Bind-mounting the raw Docker socket into a workflow runner is equivalent to
giving every workflow root on the Docker host:

- `docker run --privileged -v /:/host alpine sh` — full filesystem access
- `docker exec <other-runner> sh` — read sibling runner secrets, including
  the GitHub App installation token still resident in memory
- `docker inspect <other-runner>` — read other runners' bind mounts and env

The socket-proxy enforces a method/path allowlist (`IMAGES`, `BUILD`,
`POST`, `INFO`, `PING`) that permits image cache sharing but blocks
container inspection (`CONTAINERS` is intentionally omitted).

## What this rule forbids

In `docker-compose.yml`, none of the following may appear under any
`services.runner-*.volumes` block:

```yaml
- /var/run/docker.sock:/var/run/docker.sock        # forbidden
- /var/run/docker.sock:/var/run/docker.sock:ro     # forbidden
- ${DOCKER_SOCK}:/var/run/docker.sock              # forbidden
- type: bind, source: /var/run/docker.sock, ...    # forbidden
```

This is enforced by `.claude/hooks/block-runner-socket-mount.sh`.

## Acceptable alternatives

If a workflow truly needs `docker run` (not just `docker pull`/`docker build`),
add `CONTAINERS: 1` to the `socket-proxy` environment and **document the
cross-runner inspection risk in your security model**. Do not switch back to
raw socket mounts.

See `docs/SECURITY-REVIEW-2026-04-20.md` finding **H-1** for the original
analysis and the socket-proxy design.
