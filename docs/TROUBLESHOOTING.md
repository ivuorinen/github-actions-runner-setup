# Troubleshooting

Read top-to-bottom; each section is self-contained but they appear in the
rough order of how likely the issue is to appear during initial setup.

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
