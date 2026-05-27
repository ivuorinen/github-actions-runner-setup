# Architecture

This document describes the system design of the ephemeral GitHub Actions
self-hosted runner setup. It is intended for operators and contributors who
need to understand how the pieces fit together.

## High-level diagram

```text
┌──────────────────────────────────────────────────────────────────────┐
│                          Docker host                                 │
│                                                                      │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐               │
│  │  runner-1   │    │  runner-2   │    │  runner-3   │               │
│  │   (root)    │    │   (root)    │    │   (root)    │               │
│  │     │       │    │     │       │    │     │       │               │
│  │   gosu      │    │   gosu      │    │   gosu      │               │
│  │     ↓       │    │     ↓       │    │     ↓       │               │
│  │  runner     │    │  runner     │    │  runner     │               │
│  │  (UID 1001) │    │  (UID 1001) │    │  (UID 1001) │               │
│  └─────┬───────┘    └─────┬───────┘    └─────┬───────┘               │
│        │                  │                  │                       │
│        │ DOCKER_HOST=tcp://socket-proxy:2375 │                       │
│        └──────────────────┼──────────────────┘                       │
│                           ↓                                          │
│                   ┌───────────────┐                                  │
│                   │ socket-proxy  │  ── ro ──►  /var/run/docker.sock │
│                   │  (cap_drop)   │            (host socket)         │
│                   └───────────────┘                                  │
│                                                                      │
│  /etc/github-app/private-key.pem  (root:root mode 600)               │
│           │                                                          │
│           └─── bind ro ───►  /run/secrets/github_app_key  (in each   │
│                                                            runner)   │
└──────────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS
                              ↓
                       ┌──────────────┐
                       │ GitHub API   │
                       │ api.github.com│
                       └──────────────┘
```

## Container lifecycle

The lifecycle of a single runner container, from `docker compose up` to
its first job and the subsequent ephemeral exit:

```text
1. tini starts entrypoint.sh as root (PID 1 of the container)
2. entrypoint.sh validates env vars
3. entrypoint.sh stats the PEM:
   - owner must be UID 0
   - mode must have no group/other bits set
4. entrypoint.sh mints a JWT (RS256, iat=now-60, exp=now+540)
5. POST /app/installations/{id}/access_tokens  → installation_token (ghs_*, 1h)
6. POST /{org|repo path}/actions/runners/registration-token  → registration_token (1h)
7. POST /{org|repo path}/actions/runners/remove-token  → RUNNER_REMOVE_TOKEN (1h)
   (pre-computed so cleanup does not need to re-sign a JWT on shutdown)
8. gosu runner ./config.sh --ephemeral --token <registration_token> ...
9. Unset RUNNER_DEFAULT_LABELS / RUNNER_EXTRA_LABELS / RUNNER_LABELS / ...
10. gosu runner ./run.sh &   (background, listens for one job)
11. parent bash waits, forwarding SIGTERM/SIGINT to the listener
12. one job runs, --ephemeral causes run.sh to exit after completion
13. bash's wait returns, main() returns, EXIT trap fires
14. cleanup() runs deregister_runner if .runner is still present
15. container exits 0
16. docker compose restart policy "unless-stopped" starts the cycle again
```

## Token chain

```text
GitHub App private key (PEM, on Docker host, root:root mode 600)
        │
        │   openssl dgst -sha256 -sign  (in entrypoint.sh, as root)
        ↓
   JWT (RS256, 9 min lifetime, claims: iat/exp/iss=app_id)
        │
        │   POST /app/installations/{installation_id}/access_tokens
        ↓
   Installation token (ghs_*, 1 hour, scoped to app permissions)
        │
        ├── POST /orgs/{org}/actions/runners/registration-token
        │   POST /repos/{owner}/{repo}/actions/runners/registration-token
        ↓
   Registration token (1 hour) ── used by config.sh ──► runner registered
        │
        ├── POST /orgs/{org}/actions/runners/remove-token
        │   POST /repos/{owner}/{repo}/actions/runners/remove-token
        ↓
   Remove token (1 hour) ── used by config.sh remove ──► runner deregistered
```

All four token kinds (JWT, installation, registration, remove) are short
lived and minted in the **root** entrypoint process. They live in `bash`
shell-variable memory only; none are exported, none are written to disk,
none are passed as command-line arguments to gosu/config.sh except the
registration token (and the remove token at cleanup), which is the
documented upstream contract.

## Privilege boundary

| Process              | UID  | Capabilities                | Can read PEM?  | Can ptrace root? |
|----------------------|------|-----------------------------|----------------|------------------|
| tini + entrypoint.sh | 0    | CHOWN DAC_OVERRIDE FOWNER SETGID SETUID KILL | yes | n/a |
| config.sh (gosu)     | 1001 | inherited bounding set       | no (mode 600) | no (ptrace_scope=1) |
| run.sh (gosu)        | 1001 | inherited bounding set       | no            | no               |
| workflow job step    | 1001 | inherited bounding set       | no            | no               |

`no-new-privileges:true` ensures the runner user cannot regain root via
setuid binaries inside the container. The combination of UID-based PEM
isolation + ptrace_scope + no-new-privileges is the H-1 mitigation
described in `docs/SECURITY-REVIEW-2026-04-20.md`.

## Network model

- Runners and socket-proxy share the default Compose project network.
- Runner containers have no published ports (no `ports:` block).
- Runner containers reach the GitHub API via standard egress through the
  host's default route. There is no proxy or egress filter — operators
  who want one should add it at the host or network level.
- The socket-proxy listens on `2375/tcp` inside the Compose network and
  is only resolvable as `socket-proxy:2375` to sibling containers; the
  port is not published to the host.

## Configuration sources

In precedence order (highest wins):

1. Variables in the container's `environment:` block in
   `docker-compose.yml`
2. `.env` file (loaded by Compose via `env_file:` if present)
3. Variables provided by Coolify or the deployment platform's UI
4. Defaults baked into the docker-compose `${VAR:-default}` expansions
5. Defaults baked into `entrypoint.sh` (`: "${VAR:=default}"`)

`entrypoint.sh` reads its config from the process environment only — it
never re-reads `.env`.

## Failure modes and where they surface

| Failure                                  | Where detected             | What happens                            |
|------------------------------------------|----------------------------|------------------------------------------|
| PEM missing                              | entrypoint.sh stat check  | container exits 1, restart loop          |
| PEM wrong owner                          | entrypoint.sh stat check  | container exits 1, restart loop          |
| PEM mode too permissive                  | entrypoint.sh mode check  | container exits 1, restart loop          |
| JWT signing fails (bad PEM)              | openssl dgst exits non-0  | container exits 1, restart loop          |
| Installation token call fails (4xx/5xx)  | api() http_code check     | container exits 1, restart loop          |
| Registration token call fails            | api() http_code check     | container exits 1, restart loop          |
| Network outage during token exchange     | curl --retry 3 then fail  | container exits 1, restart loop          |
| config.sh fails                          | set -e propagation        | container exits 1, restart loop          |
| run.sh ephemeral exit (job done)         | wait loop returns         | clean exit 0, cleanup() runs deregister  |
| SIGTERM during job                       | trap _forward_to_runner   | listener finishes job, then cleanup      |
| SIGKILL                                  | uncatchable               | runner stays "offline" on GitHub side   |
| socket-proxy not healthy at startup      | depends_on healthcheck    | runner does not start until proxy is up |
| Job exceeds RUNNER_MEM_LIMIT             | kernel OOM kill           | container exits 137, restart loop        |

## What this design intentionally does NOT do

- **No persistence of registration state across container restarts.** Each
  container fetches a fresh registration token; the actions-runner state
  file (`.runner`) lives in the container's writable layer and is
  discarded when the container is replaced. This is what makes the
  runners truly ephemeral.
- **No workspace caching.** `_work` is in the container's writable layer,
  which is wiped on restart. Workflows that need a cache should use
  `actions/cache` or a runner-side bind mount they manage explicitly.
- **No PEM-on-the-fly fetch.** The PEM must be on the host filesystem
  before `docker compose up`. There is no integration with cloud KMS or
  HashiCorp Vault — those are operator concerns.
- **No outbound proxy.** Operators behind a corporate egress proxy must
  set `HTTP_PROXY`/`HTTPS_PROXY` in the runner environment manually.

## Related documents

- `SETUP.md` — step-by-step deployment guide
- `OPERATIONS.md` — day-2 operations and monitoring
- `TROUBLESHOOTING.md` — common failure scenarios
- `docs/SECURITY-REVIEW-2026-04-20.md` — security findings and mitigations
- `docs/ENVIRONMENT-VARIABLES.md` — full env var reference
- `.claude/rules/` — invariants enforced when modifying the system
