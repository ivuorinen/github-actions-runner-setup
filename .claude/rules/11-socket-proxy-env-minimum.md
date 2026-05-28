# Rule: `socket-proxy` exposes only the minimum Docker API surface

In `docker-compose.yml`, the `socket-proxy` service's `environment:` block
must enable only the Docker API endpoints that workflows genuinely need.
The current allowed surface is:

| Var | Effect |
| --- | --- |
| `IMAGES: 1` | `GET /images`, `GET /images/{name}/json` — image cache reads |
| `BUILD: 1` | `POST /build` — `docker build` |
| `POST: 1` | All HTTP `POST` verbs on allowed paths |
| `INFO: 1` | `GET /info` |
| `PING: 1` | `GET /_ping` — health verification |

`CONTAINERS`, `EXEC`, `VOLUMES`, `NETWORKS`, `SERVICES`, `TASKS`, `NODES`,
`PLUGINS`, `SECRETS`, `SWARM`, `SYSTEM` and `SESSION` are intentionally
**omitted** (default deny).

## Why each omission matters

- `CONTAINERS: 1` would let any workflow call `GET /containers/{id}/json`
  on sibling runners and read their environment variables, including
  `GITHUB_APP_INSTALLATION_ID` and any in-process credentials. It would
  also enable `POST /containers/{id}/exec` to run arbitrary commands
  inside a sibling runner — cross-runner privilege equivalent to
  mounting the host socket directly.
- `EXEC: 1` is `POST /exec/{id}/start` — same severity as `CONTAINERS`.
- `VOLUMES`, `NETWORKS`, `PLUGINS`, `SECRETS`, `SWARM` are all docker
  daemon-level mutations that workflows have no business making.

## What this rule forbids

Adding any of the following lines to the `socket-proxy.environment:` block
without an explicit `# allow-socket-proxy-rule-11` comment on the same
line AND a paragraph in `docs/SECURITY.md` documenting the operator's
threat-model accepting the consequences:

```yaml
CONTAINERS: 1
EXEC: 1
VOLUMES: 1
NETWORKS: 1
PLUGINS: 1
SECRETS: 1
SWARM: 1
TASKS: 1
SERVICES: 1
NODES: 1
SESSION: 1
SYSTEM: 1
```

## When `CONTAINERS: 1` is genuinely needed

If a workflow truly needs `docker run` (not just `docker pull` / `docker
build`), prefer one of:

1. Move that specific workflow to a separate runner pool with its own
   socket-proxy and a stricter network policy.
2. Use a sidecar service rather than `docker run` (e.g. compose service
   started ahead of time).
3. Accept the cross-runner risk and document it in `docs/SECURITY.md`
   under "What is explicitly NOT defended". In that case, also add the
   `# allow-socket-proxy-rule-11` annotation referenced above.

See `docs/SECURITY.md` and `docs/SECURITY-REVIEW-2026-04-20.md` finding
**H-1** for the rationale behind the socket-proxy boundary.

## Verification

```bash
grep -nE '^[[:space:]]+(CONTAINERS|EXEC|VOLUMES|NETWORKS|PLUGINS|SECRETS|SWARM|TASKS|SERVICES|NODES|SESSION|SYSTEM):' docker-compose.yml
```

Must produce no output (or only lines carrying the `allow-socket-proxy-rule-11`
annotation).
