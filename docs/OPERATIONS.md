# Operations

Day-2 operations guide for the ephemeral runner fleet. Covers what to
monitor, how to scale, how to rotate credentials, and how to upgrade.

## Routine monitoring

### What "healthy" looks like

```bash
docker compose ps
```

Expected output: every runner service in `running` state, socket-proxy in
`running (healthy)`. The runner Docker `HEALTHCHECK` looks for a
`Runner.Listener` or `run.sh` process inside the container; it goes
healthy ~30s after startup once `config.sh` completes.

### Logs

```bash
docker compose logs --since 10m -f runner-1
docker compose logs --since 10m -f socket-proxy
```

Key log lines from `entrypoint.sh`:

| Line                                       | Meaning                                |
|--------------------------------------------|----------------------------------------|
| `Configuring runner <name> for <url>`      | About to call `config.sh` (success indicator) |
| `Runner group: <name>`                     | Org-scoped runner with explicit group  |
| `Unsetting post-registration configuration variables` | Pre-listener cleanup done       |
| `Starting runner listener`                 | `run.sh` backgrounded, job-wait begins |
| `Received SIGTERM, forwarding to runner listener` | Graceful shutdown in progress |
| `Removing runner registration`             | Cleanup path triggered                 |
| `Warning: failed to deregister runner`     | Deregister errored; manual cleanup may be needed |
| `ERROR: ...`                                | Fatal — see Troubleshooting             |

### GitHub-side visibility

- Org runners: `https://github.com/organizations/<ORG>/settings/actions/runners`
- Repo runners: `https://github.com/<owner>/<repo>/settings/actions/runners`

Each ephemeral container appears, executes one job, and disappears from
the list within ~30s of completion. A runner that lingers as "offline"
for more than a minute is a deregistration failure — see Troubleshooting.

## Scaling

### Vertical (more CPU/RAM per runner)

Set `RUNNER_MEM_LIMIT`, `RUNNER_CPUS`, `RUNNER_PIDS_LIMIT`, and
`RUNNER_NOFILE_*` in `.env`. Defaults are conservative
(4 GiB / 2 CPUs / 1024 pids / 4096 file descriptors). Pick values that
leave headroom for the socket-proxy and for the host OS.

### Horizontal (more concurrent jobs)

Add `runner-4`, `runner-5`, … service blocks in `docker-compose.yml` by
copying an existing one (see `SETUP.md` §9 for the full template). Then:

```bash
docker compose up -d --no-recreate
```

This brings up new runners without restarting existing ones. Existing
ephemeral runners will drain naturally as they pick up jobs.

### How many runners do I need?

Rule of thumb: max number of concurrent jobs you ever want to run on this
host, plus 1 for headroom. Each runner consumes ~150 MiB resident memory
at idle, plus the workflow's own memory during a job.

## Updating

### Updating the base runner image

The `Dockerfile`'s `FROM` line is digest-pinned and managed by Renovate.
A Renovate PR will appear when GitHub publishes a new
`ghcr.io/actions/actions-runner` release. Merge the PR, then:

```bash
docker compose build --pull
docker compose up -d
```

Compose will rebuild the image and recreate runners one at a time
(existing in-flight jobs finish first because of `stop_grace_period`).

### Updating the socket-proxy

Same pattern — Renovate manages the digest pin. The proxy is unrelated to
in-flight jobs, but updating it restarts it briefly. To avoid disrupting
running jobs:

```bash
docker compose up -d socket-proxy
# wait for healthcheck
docker compose ps socket-proxy
```

The runners stay up; their `DOCKER_HOST` connection re-establishes on next
use.

## Credential rotation

### Rotating the GitHub App private key

1. In the GitHub App settings, generate a new private key. **Do not delete
   the old key yet.**
2. Copy the new PEM to the Docker host. **Do not overwrite the existing
   file in place** — write to a new path first, then atomic-rename.

   ```bash
   cp new-key.pem /etc/github-app/private-key.pem.new
   chown 0:0 /etc/github-app/private-key.pem.new
   chmod 600 /etc/github-app/private-key.pem.new
   mv /etc/github-app/private-key.pem.new /etc/github-app/private-key.pem
   ```

3. Restart the runners to pick up the new key on next JWT mint:

   ```bash
   docker compose restart runner-1 runner-2 runner-3
   ```

   The PEM is read on every container start, so a restart is sufficient —
   no rebuild needed.

4. Verify a new runner registers successfully on GitHub.
5. Delete the old key in the GitHub App settings.

### Rotating the App installation

If you re-install the GitHub App in a new org/repo, update
`GITHUB_APP_INSTALLATION_ID` in `.env` and restart all runners.

### Renaming or changing scope

If you switch from `RUNNER_SCOPE=repo` to `org` (or vice versa):

1. Update `RUNNER_SCOPE` in `.env`.
2. Set the matching `GITHUB_ORG` or `GITHUB_REPO_OWNER` + `GITHUB_REPO_NAME`.
3. Update App permissions on GitHub (org needs *Self-hosted runners
   read/write*; repo needs *Administration read/write*).
4. `docker compose down && docker compose up -d`. Down first — restart
   is not enough because the GitHub-side runners are scoped differently.

## Adding a runner group (org scope)

1. Create the runner group in your org settings.
2. Set `RUNNER_GROUP=<group-name>` in `.env`.
3. Restart the runners. Each one re-registers into the new group.
4. Verify on the GitHub side that the runners appear in the right group.

## Backups

Nothing in this setup needs backups beyond:

- `docker-compose.yml` and `.env` — version control them, but **never
  commit `.env`** (it contains `GITHUB_APP_INSTALLATION_ID` and may
  contain private hostnames).
- The GitHub App PEM file. Store a copy in your secret manager. The PEM
  can be regenerated from the GitHub App at any time — rotation is
  faster than restoring a backup, so the PEM's "backup" is really just
  the App configuration itself.

The runners themselves hold no durable state worth backing up — that is
the point of "ephemeral".

## Decommissioning

```bash
docker compose down
```

This sends SIGTERM to every runner, which:

1. Forwards SIGTERM to `Runner.Listener`
2. Finishes the in-flight job (if any) up to the `stop_grace_period` (2 min)
3. Deregisters from GitHub via `config.sh remove`
4. Exits

If a runner does not deregister cleanly (logs show
`Warning: failed to deregister runner`), use the GitHub UI or the
`DELETE /orgs/{org}/actions/runners/{runner_id}` API to clean up the
orphan registration. Stale registrations do not pose a security risk
(they cannot accept new jobs), but they look untidy.

## Performance tuning

### Faster docker image pulls

The socket-proxy shares the host Docker image cache across all runners.
Workflows that pull the same image (e.g. `node:20`) benefit automatically
on the second pull. To prewarm the cache:

```bash
docker pull node:20
docker pull python:3.12
```

The pulls land in the host daemon's image store; the next workflow that
references those images skips the pull.

### Reducing container start time

Ephemeral containers restart between every job. The cold-start cost is
~5s (image instantiate + token exchange). To reduce it:

- Keep the base image small (the runner image is ~1.8 GB already; don't
  add tools you don't need).
- Use a fast SSD on the Docker host.
- Keep `GITHUB_API_URL` resolution warm (`/etc/hosts` entry).

### Reducing API call latency

Each token exchange is 2-3 HTTPS round trips. On a typical link this adds
~500-800 ms. If you need this lower, run the runners geographically close
to `api.github.com` (US East). There is no GitHub-side caching for these
endpoints.

## Running behind a corporate proxy

`entrypoint.sh` uses `curl` for every GitHub API call. `curl` honours the
standard `HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY` environment variables.
To route all runner outbound through a proxy, add the following to each
runner service's `environment:` block in `docker-compose.yml`:

```yaml
HTTPS_PROXY: ${HTTPS_PROXY:-}
HTTP_PROXY:  ${HTTP_PROXY:-}
NO_PROXY:    ${NO_PROXY:-socket-proxy,localhost,127.0.0.1}
```

Then set the values in `.env`. The `socket-proxy` hostname should always
appear in `NO_PROXY` — Docker API calls from the runner go through the
local sidecar and should never traverse the corporate proxy.

The runner listener itself (Microsoft's `Runner.Listener`) also reads
these environment variables. Workflow steps inherit them through the
runner environment.

## DNS / IPv6

`api.github.com` is **IPv4-only** at the time of writing (no AAAA
record). On hosts without IPv4 connectivity to api.github.com, the
runner will fail at token-exchange time. Verify with:

```bash
dig +short A api.github.com   # should return 140.82.112.x or similar
```

If you operate on an IPv6-only network, either configure a NAT64/DNS64
gateway or run a small IPv4 jump host that the runner traffic transits.

## See also

- `TROUBLESHOOTING.md` — what to do when things break
- `docs/ARCHITECTURE.md` — how the system fits together
- `docs/ENVIRONMENT-VARIABLES.md` — full env var reference
