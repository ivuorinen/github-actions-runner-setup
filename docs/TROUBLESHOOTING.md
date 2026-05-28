# Troubleshooting

Read top-to-bottom; each section is self-contained but they appear in the
rough order of how likely the issue is to appear during initial setup.

## "Required environment variable is missing: \<NAME\>"

```text
[entrypoint] ERROR: Required environment variable is missing: GITHUB_APP_ID
```

Set the named variable in `.env` (or inject it via Coolify's environment
panel). The complete reference is in `docs/ENVIRONMENT-VARIABLES.md`.
Minimum set: `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`,
`GITHUB_APP_PRIVATE_KEY_FILE`, `RUNNER_SCOPE`, `RUNNER_WORKDIR`, plus
either `GITHUB_ORG` (org scope) or `GITHUB_REPO_OWNER` + `GITHUB_REPO_NAME`
(repo scope).

## "entrypoint.sh must run as root (UID 0)"

```text
[entrypoint] ERROR: entrypoint.sh must run as root (UID 0), got UID 1001
```

Something overrode the container's user. Check `docker-compose.yml` for an
accidental `user:` key on a runner service — there should be none. The
Dockerfile ends with `USER root` deliberately so that the entrypoint can
read the PEM (UID 0, mode 600) before dropping privileges via gosu. See
`.claude/rules/01-pem-must-be-root-mode-600.md`.

## "Key file is not readable by root"

```text
[entrypoint] ERROR: Key file is not readable by root: /run/secrets/github_app_key
```

The PEM is bind-mounted but `chmod` denies even root read. This is rare
but happens if the host file mode was `0000`. Fix on the host:

```bash
chmod 600 /etc/github-app/private-key.pem
chown 0:0 /etc/github-app/private-key.pem
docker compose restart
```

## "Network error calling POST \<url\>"

```text
[entrypoint] ERROR: Network error calling POST https://api.github.com/app/installations/...
```

curl could not reach api.github.com (or your GHES API). Common causes:

- DNS resolution failure — `docker compose exec runner-1 getent hosts api.github.com`
- Corporate proxy not configured — set `HTTPS_PROXY` per `docs/OPERATIONS.md`
- IPv6-only network where api.github.com has no AAAA record — see
  `docs/OPERATIONS.md` "DNS / IPv6"
- GHES instance unreachable — confirm `GITHUB_API_URL` is correct and the
  cert chain is trusted by the container

Token-exchange retries: 3 attempts with curl exponential backoff and a
per-attempt cap of 60 seconds (180s worst case).

## "API returned no token" or "suspiciously short token"

```text
[entrypoint] ERROR: API returned no token: <github-side message>
[entrypoint] ERROR: API returned a suspiciously short token (length 3)
```

GitHub responded but the `token` field was missing, null, or unreasonably
short. The accompanying message is the `.message` field from GitHub's JSON
response. Common causes:

- The GitHub App lost the required permission (re-grant Self-hosted runners
  read+write, or repo Administration read+write).
- The installation was deleted or suspended.
- A transient GitHub-side outage during partial degradation.

Re-run after the underlying condition is fixed — the runner does not retry
this class of error.

## "RUNNER_LABELS is empty"

```text
[entrypoint] ERROR: RUNNER_LABELS is empty — set RUNNER_DEFAULT_LABELS or RUNNER_EXTRA_LABELS
```

You explicitly cleared `RUNNER_DEFAULT_LABELS` AND `RUNNER_EXTRA_LABELS`
(or set `RUNNER_LABELS=` directly to empty). At least one of these must
be non-empty. The default value
`self-hosted,linux,x64,docker,ephemeral` is sufficient by itself.

## "Key file not found"

```text
[entrypoint] ERROR: Key file not found: /run/secrets/github_app_key
```

The bind mount did not happen. Check:

```bash
docker compose config | grep -A2 volumes
docker compose exec runner-1 ls -la /run/secrets/
```

If `/run/secrets/github_app_key` is missing inside the container, the
volume entry in `docker-compose.yml` did not resolve. Confirm
`GITHUB_APP_PRIVATE_KEY_HOST_PATH` is set in `.env` to the absolute host
path, and that the path exists on the host.

## "Key file must be owned by UID 0 (root)"

```text
[entrypoint] ERROR: Key file must be owned by UID 0 (root) inside the
container ... got UID 1001
```

Fix on the host:

```bash
chown 0:0 /etc/github-app/private-key.pem
chmod 600 /etc/github-app/private-key.pem
docker compose restart
```

This is **required** for the H-1 mitigation; do not work around it by
running the entrypoint as the runner user.

## "Key file permissions must not grant any access to group or other"

```text
[entrypoint] ERROR: Key file permissions must not grant any access to
group or other users; got mode 644
```

Fix:

```bash
chmod 600 /etc/github-app/private-key.pem
docker compose restart
```

The check accepts: `400`, `600`, `700`. Anything with group or other
read/write/execute bits is rejected.

## "API POST ... returned HTTP 401: Bad credentials"

The JWT was rejected. Causes:

| Cause                                 | How to verify                              |
|---------------------------------------|--------------------------------------------|
| Wrong `GITHUB_APP_ID`                 | Open the GitHub App settings, confirm the ID matches |
| PEM does not belong to this App       | Regenerate the PEM in GitHub App settings  |
| System clock skew on the Docker host  | `date -u` on host vs `https://time.is`     |
| PEM corrupted during copy             | `openssl rsa -in <pem> -noout -check`      |

Note on clock skew: the JWT uses `iat=now-60` for tolerance, and GitHub
accepts JWTs up to 10 minutes before now. If the host clock is more than
~10 min off, every JWT is rejected.

## "API POST ... returned HTTP 404: Not Found"

The installation ID, org name, or repo name is wrong, OR the App is not
installed where you think it is.

```bash
# Verify the installation exists for this App:
docker compose run --rm runner-1 bash -c '
  jwt=$(/usr/local/bin/entrypoint.sh helper-mint-jwt 2>/dev/null || true)
  curl -sSL -H "Authorization: Bearer $jwt" -H "Accept: application/vnd.github+json" \
    https://api.github.com/app/installations
'
```

(`entrypoint.sh helper-mint-jwt` is a future helper — for now, use
`gh api` from a workstation with the App's installation context.)

If the App is installed in a different org than `GITHUB_ORG`, the install
ID will not match. Re-install the App in the target org or update
`GITHUB_ORG`.

## "API POST ... returned HTTP 403: Resource not accessible by integration"

The App lacks the required permission.

- Org runners: needs **Self-hosted runners: Read and write**
- Repo runners: needs **Administration: Read and write**

Add the permission in GitHub App settings, then accept the install
permission change for each existing installation (GitHub does not
re-grant new permissions automatically — install owners must approve).

## "RUNNER_SCOPE must be 'org' or 'repo'"

The `.env` or environment overrides set `RUNNER_SCOPE` to something
unexpected (often whitespace from copy-paste).

```bash
docker compose exec runner-1 sh -c 'echo "[$RUNNER_SCOPE]"'
# Expected: [org] or [repo] — anything with extra spaces or chars is wrong
```

## Runner registers but no jobs ever land on it

The workflow's `runs-on:` labels do not match the runner's labels exactly.

Compare:

```yaml
# In workflow
runs-on: [self-hosted, linux, x64, docker, ephemeral, lint, small]
```

```bash
# Active labels on runner-1
docker compose exec runner-1 sh -c '
  printenv RUNNER_DEFAULT_LABELS RUNNER_EXTRA_LABELS
'
```

GitHub matches labels exactly (case sensitive, comma-separated). Common
mistakes:

- Workflow uses `Linux` (capital L), runner has `linux`.
- Workflow uses `self_hosted`, runner has `self-hosted`.
- Workflow expects the `RUNNER_GROUP`, but the App lacks
  *Self-hosted runners* permission, so the runner registered without the
  group.

## Runner shows as offline immediately after a job

This is **expected** — ephemeral runners exit after one job, and the
restart policy brings up a fresh container. The new container registers
as a new runner (same name if `RUNNER_INSTANCE_NAME` is set, or a fresh
random suffix otherwise).

If the old registration *lingers* as offline for more than a minute, the
deregister call failed. Check the runner logs:

```bash
docker compose logs runner-1 | tail -50
```

Look for `Warning: failed to deregister runner` followed by an HTTP
error from `config.sh remove`. Clean up the orphan via the GitHub UI or
the API:

```bash
gh api -X DELETE /orgs/<ORG>/actions/runners/<RUNNER_ID>
```

## socket-proxy reports unhealthy or `_ping` fails

```bash
docker compose ps
# socket-proxy ... (unhealthy)
```

The proxy healthcheck is `wget --spider http://127.0.0.1:2375/_ping`.
Failure modes:

- **Host `/var/run/docker.sock` not mounted or missing.** The bind mount
  in `docker-compose.yml` `socket-proxy.volumes:` points to the host
  socket. On Coolify, the deployment must explicitly allow that mount.
  Verify on the host:

  ```bash
  ls -la /var/run/docker.sock
  ```

- **Host Docker daemon stopped or restarting.** Restart `docker.service`
  on the host (systemd) or via Docker Desktop UI.

- **`PING: 1` accidentally removed from `socket-proxy.environment:`.**
  Without it the proxy returns 403 on `/_ping`, marking the container
  unhealthy. See `.claude/rules/11-socket-proxy-env-minimum.md`.

If the proxy is unhealthy, runners will fail their `depends_on` startup
condition (Compose blocks runners from starting). Workflows that
require `docker pull` / `docker build` will fail at runtime even after
runners start, because the proxy mediates all Docker calls.

## "docker: Cannot connect to the Docker daemon"

Inside a job step that runs `docker run` / `docker pull`:

```text
docker: Cannot connect to the Docker daemon at tcp://socket-proxy:2375
```

Check:

```bash
docker compose ps socket-proxy
docker compose logs --tail=50 socket-proxy
docker compose exec runner-1 nc -z socket-proxy 2375 && echo OK
```

If `nc -z` fails, the socket-proxy is not reachable from the runner.
Usually because:

- `socket-proxy` failed its healthcheck (check its logs).
- `/var/run/docker.sock` does not exist on the host (you are inside a
  different runtime — podman, containerd direct).
- Coolify's deployment isolation disallows the socket bind mount. Enable
  it in the app settings.

## "permission denied while trying to connect to the Docker daemon socket"

The socket-proxy is reachable but rejects the call. This means the call
needs a Docker API endpoint that is not allowed by the proxy's
environment variables (`IMAGES`, `BUILD`, `POST`, `INFO`, `PING`).

Most likely cause: a job uses `docker run` or `docker exec`. These need
the `CONTAINERS` permission, which is intentionally disabled (see
`docs/SECURITY-REVIEW-2026-04-20.md` §3). Options:

1. Restructure the workflow to use `docker build` / `docker pull` only.
2. Add `CONTAINERS: 1` to the socket-proxy environment — **only for
   trusted workflows**, because it re-enables cross-runner inspection.

## "actions/checkout fails with: HEAD detached"

The default workspace `_work` lives in the container's writable layer.
If a previous run wrote to it, the next ephemeral container does not
inherit that state — but checkout is happy with that. If you see this
error, your workflow is doing something unusual (e.g. self-hosted-runner
caching that assumes persistent `_work`). Disable that caching.

## Container OOM-killed (exit code 137)

The job exceeded `RUNNER_MEM_LIMIT` (default 4 GiB). The kernel killed
the container.

```bash
docker compose ps -a
# Look for "Exited (137)"
```

Bump `RUNNER_MEM_LIMIT` in `.env`:

```dotenv
RUNNER_MEM_LIMIT=8g
```

Then `docker compose up -d` (Compose recreates containers when limits
change).

## High disk usage on the host

The host Docker daemon caches every image pulled by every workflow.
Periodically prune:

```bash
docker image prune -af --filter "until=168h"   # remove images unused for a week
docker builder prune -af                       # remove buildx cache
```

These are safe operations — the next workflow that needs an image will
re-pull. The socket-proxy does not prevent these prune calls (`POST` is
allowed).

## "Error response from daemon: pull access denied for ghcr.io/<...>"

The workflow tried to pull a private image and the runner is not
authenticated to that registry. Either:

1. Use `docker/login-action` in the workflow with a GHCR token from
   secrets.
2. Configure host-level `~/.docker/config.json` (this propagates through
   the socket-proxy because the daemon resolves auth, not the proxy).

## Logs are spammed with `proxying X to /var/run/docker.sock`

The socket-proxy's default log level is INFO. We set `LOG_LEVEL: warning`
in `docker-compose.yml`; if you see DEBUG/INFO spam, you have an older
docker-compose.yml without the override. Pull the latest.

## "I changed `.env` and nothing happens"

Compose only re-reads `.env` on `docker compose up`, not on `restart`.
After editing `.env`:

```bash
docker compose up -d
```

If you only need to restart one runner with the new vars:

```bash
docker compose up -d runner-1
```

## Still stuck?

1. Capture full state:

   ```bash
   docker compose ps
   docker compose config
   docker compose logs --since 30m > runner-logs.txt
   ```

2. Run the lint suite to rule out config drift:

   ```bash
   pre-commit run --all-files
   ```

3. Open a bug report at
   <https://github.com/ivuorinen/github-actions-runner-setup/issues/new?template=bug_report.md>
   and attach the logs (with secrets redacted — see the issue template).
