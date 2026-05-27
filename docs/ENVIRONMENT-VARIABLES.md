# Environment variables — complete reference

Every variable read by `entrypoint.sh`, `docker-compose.yml`, or the
runner itself. Use this as the source of truth — `.env.example` matches
this document but is comment-only and may have ordering/grouping that
differs.

Legend:

- **Required**: container will refuse to start without this
- **Default**: shown in `code` — what happens if the variable is unset
- **Where read**: `entrypoint.sh` / `docker-compose.yml` / both

---

## GitHub App authentication

### `GITHUB_APP_ID`

- **Required.** Numeric ID of the GitHub App. Visible in the App's
  settings page URL: `https://github.com/settings/apps/<slug>` shows
  "App ID: 1234567" in the upper-right corner.
- Where read: both. `entrypoint.sh` uses it for the JWT `iss` claim.
- Sensitivity: not secret — visible to anyone who can list installations,
  but reveals which org installed the app.

### `GITHUB_APP_INSTALLATION_ID`

- **Required.** Numeric ID of the **installation** of the App in the
  target org/account. Different from the App ID — every install gets a
  new install ID.
- Find it: in the GitHub App settings → "Install App" → click the install
  → URL shows `/installations/<install-id>`. Or via API:
  `GET /app/installations` with a JWT.
- Where read: both. `entrypoint.sh` uses it in the
  `/app/installations/{id}/access_tokens` path.
- Sensitivity: not secret on its own — useless without the PEM.

### `GITHUB_APP_PRIVATE_KEY_HOST_PATH`

- **Required** when using `docker-compose.yml`. Absolute path on the
  Docker host to the PEM file the GitHub App generated.
- The file must be `chown 0:0`, mode `0600`. The compose file
  bind-mounts this path read-only into each runner at
  `/run/secrets/github_app_key`.
- Where read: `docker-compose.yml` only.
- Sensitivity: **critical**. Anyone with read access to this file can
  mint installation tokens.

### `GITHUB_APP_PRIVATE_KEY_FILE`

- **Required** inside the container. Path inside the container where
  the PEM is readable. Defaults to `/run/secrets/github_app_key` via
  the compose `environment:` block.
- Operators do not need to set this manually unless they run the
  container outside of `docker-compose.yml`.
- Where read: `entrypoint.sh`.

### `GITHUB_HOST`

- **Optional.** Default: `github.com`.
- For **GitHub Enterprise Server (GHES)**, set this to your instance
  hostname (e.g. `ghes.example.com`) and `entrypoint.sh` will derive
  `GITHUB_API_URL=https://<host>/api/v3` and `GITHUB_WEB_URL=https://<host>`
  automatically.
- If you set `GITHUB_API_URL` and/or `GITHUB_WEB_URL` directly, those
  explicit values take precedence over the `GITHUB_HOST` derivation —
  useful for GHES instances that put the API on a separate subdomain.
- Where read: `entrypoint.sh` (host → URL derivation) and
  `docker-compose.yml` (passes the value into the container).

### `GITHUB_API_URL`

- **Optional.** Default: `https://api.github.com`.
- Override for GitHub Enterprise Server. Example: `https://ghes.example.com/api/v3`.
- Where read: both.

### `GITHUB_WEB_URL`

- **Optional.** Default: `https://github.com`.
- Override for GitHub Enterprise Server. Example: `https://ghes.example.com`.
- Used to construct the `--url` argument to `config.sh` (e.g.
  `https://github.com/myorg`).
- Where read: both. Unset post-registration if `UNSET_CONFIG_VARS=true`.

---

## Runner scope

### `RUNNER_SCOPE`

- **Required.** One of `org` or `repo`.
- Determines the API path used for registration/remove tokens, and the
  shape of the `config.sh --url` argument.
- Where read: `entrypoint.sh`.

### `GITHUB_ORG`

- **Required when `RUNNER_SCOPE=org`.** Organization login (e.g. `myorg`,
  not the display name).
- Where read: `entrypoint.sh`. Kept after registration for cleanup.

### `GITHUB_REPO_OWNER`

- **Required when `RUNNER_SCOPE=repo`.** Repo owner login.
- Where read: `entrypoint.sh`.

### `GITHUB_REPO_NAME`

- **Required when `RUNNER_SCOPE=repo`.** Repo name (no owner prefix).
- Where read: `entrypoint.sh`.

### `RUNNER_GROUP`

- **Optional.** Default: `Default`. Org-scope only. Name of the runner
  group to register into.
- Ignored when `RUNNER_SCOPE=repo` (repo-scope runners cannot be grouped).
- Where read: `entrypoint.sh`. Passed as `--runnergroup` to `config.sh`.

---

## Runner identity and labels

### `RUNNER_INSTANCE_NAME`

- **Optional.** If empty, the runner registers as
  `<hostname>-<unix-timestamp>`. Set this to override.
- Per-runner instance variables `RUNNER_1_NAME`, `RUNNER_2_NAME`, … in
  `.env` map to this for each service.
- Where read: `entrypoint.sh`. Unset post-registration.

### `RUNNER_DEFAULT_LABELS`

- **Required.** Default: `self-hosted,linux,x64,docker,ephemeral`.
- Comma-separated. Applied to every runner.
- Where read: `entrypoint.sh`. Unset post-registration.

### `RUNNER_EXTRA_LABELS`

- **Optional.** Per-runner additional labels (comma-separated).
- `entrypoint.sh` concatenates `${RUNNER_DEFAULT_LABELS},${RUNNER_EXTRA_LABELS}`
  (no trailing comma when extra is empty).
- Mapped from `RUNNER_<N>_LABELS` per runner in `.env` to
  `RUNNER_EXTRA_LABELS` inside each service.
- Where read: `entrypoint.sh`. Unset post-registration.

### `RUNNER_LABELS`

- **Optional.** If non-empty, replaces the default+extra concatenation
  entirely. Use only for bare `docker run` invocations that bypass the
  `RUNNER_DEFAULT_LABELS` + `RUNNER_EXTRA_LABELS` pattern.
- Where read: `entrypoint.sh`. Unset post-registration.

### `RUNNER_<N>_LABELS` and `RUNNER_<N>_NAME` (`.env` only)

- Per-runner shorthand variables read by `docker-compose.yml`, e.g.
  `RUNNER_1_LABELS=lint,small`. These are not read by `entrypoint.sh`
  directly — they map into `RUNNER_EXTRA_LABELS` and
  `RUNNER_INSTANCE_NAME` per service.
- Where read: `docker-compose.yml`.

### `RUNNER_CONTAINER_PREFIX`

- **Optional.** Default: `gha-runner`. Used as the hostname prefix
  (`gha-runner-1`, `gha-runner-2`, …).
- Where read: `docker-compose.yml`.

---

## Runner runtime configuration

### `RUNNER_WORKDIR`

- **Required.** Default: `/home/runner/_work`. Working directory for
  workflow checkouts.
- Where read: `entrypoint.sh`. Passed as `--work` to `config.sh`. Unset
  post-registration.

### `RUNNER_UID`

- **Optional.** Default: `1001`. UID of the runner user inside the
  container. Used only for the tmpfs `/runner-tmp` mount owner.
- Verify the actual UID with:
  `docker run --rm ghcr.io/actions/actions-runner:<tag> id runner`.
- Where read: `docker-compose.yml`.

### `RUNNER_IMAGE_NAME`

- **Optional.** Default: `local/github-app-actions-runner:latest`.
  Image tag for the locally-built runner image.
- Where read: `docker-compose.yml`. Useful when pulling a pre-built
  image from a registry.

### `UNSET_CONFIG_VARS`

- **Optional.** Default: `true`. If `true`, `entrypoint.sh` unsets all
  registration-only env vars after `config.sh` completes, so they are
  not inherited by workflow job processes. Set to `false` only when
  debugging variable propagation.
- Where read: `entrypoint.sh`.

---

## Resource limits

### `RUNNER_MEM_LIMIT`

- **Optional.** Default: `4g`. Per-runner memory limit (Docker
  `mem_limit`). Container is OOM-killed (exit 137) if exceeded.
- Where read: `docker-compose.yml`.

### `RUNNER_CPUS`

- **Optional.** Default: `2`. Per-runner CPU shares (Docker `cpus`).
  Fractional values allowed (`1.5`).
- Where read: `docker-compose.yml`.

### `RUNNER_PIDS_LIMIT`

- **Optional.** Default: `1024`. Maximum process/thread count per
  runner. Prevents fork bombs.
- Where read: `docker-compose.yml`.

### `RUNNER_NOFILE_SOFT` / `RUNNER_NOFILE_HARD`

- **Optional.** Defaults: `4096` / `8192`. ulimit on open file
  descriptors per runner. Bump if a workflow opens many sockets or
  file handles (e.g. parallel browser tests).
- Where read: `docker-compose.yml`.

### `RUNNER_STOP_GRACE`

- **Optional.** Default: `2m`. Time docker waits between SIGTERM and
  SIGKILL during `docker stop` / `docker compose down`. Tune up if
  you frequently have long-running jobs that need more drain time.
- Where read: `docker-compose.yml`.

### `PROXY_MEM_LIMIT` / `PROXY_PIDS_LIMIT`

- **Optional.** Defaults: `128m` / `64`. Resource limits for the
  socket-proxy sidecar.
- Where read: `docker-compose.yml`.

---

## DOCKER_HOST

`DOCKER_HOST` is hard-coded in each runner service's `environment:`
block to `tcp://socket-proxy:2375`. It is not configurable via `.env`
because changing it would break the socket-proxy isolation. If you have
a reason to change it (e.g. an external Docker host), edit
`docker-compose.yml` directly and review the security implications in
`docs/SECURITY-REVIEW-2026-04-20.md`.

---

## Sensitivity summary

| Sensitivity | Variables | Storage |
|-------------|-----------|---------|
| Critical (secret) | The PEM file itself | Host filesystem, root:root mode 600. **Never** in `.env`. |
| Sensitive (private) | `GITHUB_APP_INSTALLATION_ID` | `.env` — do not commit |
| Identifying | `GITHUB_APP_ID`, `GITHUB_ORG`, `GITHUB_REPO_*` | `.env` — do not commit |
| Operational | All `RUNNER_*` variables | `.env` or `.env.example` — safe to commit defaults |

The `.gitignore` excludes `.env` by default. **Always** verify before
committing that `.env` is not staged. The pre-commit hook
`detect-private-key` catches PEM material if it ever ends up in a
tracked file.
