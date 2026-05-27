# Self-hosted GitHub Actions runners

Ephemeral self-hosted GitHub Actions runners. Each runner registers with
GitHub via a **GitHub App**, executes exactly one job, deregisters, and
Docker restarts a fresh container. The system is designed for Coolify
but works on any Docker Engine 20.10+ host.

## Why this exists

- GitHub Personal Access Tokens for runner registration are clunky, long-lived,
  and rotate poorly. GitHub App authentication mints short-lived
  installation tokens with narrowly-scoped permissions, refreshed on every
  container start.
- Ephemeral runners give you fresh state per job, which means workflows
  cannot poison each other through `_work` cache, environment leftovers,
  or leftover docker images.
- Docker pull caching is preserved across job boundaries via a shared
  `socket-proxy` sidecar — runs that depend on the same base images are
  fast.

## Documentation map

- **[`SETUP.md`](SETUP.md)** — step-by-step deployment from scratch to a
  running fleet.
- **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** — how the system
  fits together, container lifecycle, token chain.
- **[`docs/OPERATIONS.md`](docs/OPERATIONS.md)** — day-2 ops, scaling,
  credential rotation, decommissioning.
- **[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)** — common
  failures and fixes.
- **[`docs/ENVIRONMENT-VARIABLES.md`](docs/ENVIRONMENT-VARIABLES.md)** —
  every env var the system reads, with defaults and sensitivity.
- **[`docs/SECURITY.md`](docs/SECURITY.md)** — threat model and
  defensive choices.
- **[`docs/SECURITY-REVIEW-2026-04-20.md`](docs/SECURITY-REVIEW-2026-04-20.md)** —
  formal security review and remediation status.
- **[`CONTRIBUTING.md`](CONTRIBUTING.md)** — how to make changes safely.
- **[`SECURITY.md`](SECURITY.md)** (root) — how to report a vulnerability.
- **[`CHANGELOG.md`](CHANGELOG.md)** — release notes and notable changes.

## Features

- **GitHub App authentication.** No long-lived PATs. JWT → installation
  token → registration token, all short-lived.
- **Ephemeral runners.** One job per container. Auto-deregister on
  exit.
- **Shared Docker image cache.** All runners reach the host Docker
  daemon through a single `socket-proxy` sidecar, so layer caches are
  shared. Cross-runner inspection is blocked.
- **Hardened by default.** `cap_drop: ALL` + minimal `cap_add`,
  `no-new-privileges`, ulimits, `pids_limit`, `mem_limit`, tmpfs for
  scratch space. The runner user (UID 1001) cannot read the GitHub App
  private key (root-owned, mode 600).
- **Coolify-compatible.** `env_file: required: false` so Coolify can
  inject env vars directly. No hard dependency on Coolify.
- **Renovate keeps base images and pre-commit pins current.**

## Quick start

1. Create a GitHub App with:
   - **Org scope**: *Self-hosted runners: Read and write* + *Metadata: Read*
   - **Repo scope**: *Administration: Read and write* + *Metadata: Read*
2. Install the App in the target org or repo. Note the App ID and
   Installation ID.
3. Copy the PEM to the Docker host, owned by root, mode 600:

   ```bash
   cp my-app.pem /etc/github-app/private-key.pem
   chown 0:0 /etc/github-app/private-key.pem
   chmod 600 /etc/github-app/private-key.pem
   ```

4. Copy `.env.example` to `.env` and fill in `GITHUB_APP_ID`,
   `GITHUB_APP_INSTALLATION_ID`, `GITHUB_APP_PRIVATE_KEY_HOST_PATH`,
   `RUNNER_SCOPE`, and either `GITHUB_ORG` or
   `GITHUB_REPO_OWNER`/`GITHUB_REPO_NAME`.
5. `make up` (or `docker compose up -d`).
6. Verify the runners appear in your org or repo's Actions settings.
7. Target the runners in workflows with `runs-on:` labels that match
   `RUNNER_DEFAULT_LABELS` + the runner's `RUNNER_<N>_LABELS`.

Full step-by-step guide in [`SETUP.md`](SETUP.md).

## Requirements

- Docker Engine 20.10+
- Docker Compose v2.24+ (required for `env_file: required: false` syntax)
- A GitHub App with the permissions listed above
- A Docker host where `/var/run/docker.sock` is mountable (the
  socket-proxy needs this)

## Example workflow

```yaml
name: lint
on:
  push:
  pull_request:

jobs:
  lint:
    runs-on: [self-hosted, linux, x64, docker, ephemeral, lint, small]
    steps:
      - uses: actions/checkout@v4
      - run: docker version
      - run: echo "Runner is working"
```

The `runs-on:` label set must exactly match (case-sensitive)
`RUNNER_DEFAULT_LABELS` + at least one runner's `RUNNER_<N>_LABELS`.

## Adding more runners

Copy a `runner-*` service block in `docker-compose.yml` and change:

- service name (`runner-4`)
- hostname (uses `RUNNER_CONTAINER_PREFIX`)
- `RUNNER_INSTANCE_NAME` → `RUNNER_4_NAME`
- `RUNNER_EXTRA_LABELS` → `RUNNER_4_LABELS`

Full template in [`SETUP.md`](SETUP.md#9-add-more-runners).

`RUNNER_DEFAULT_LABELS` provides the shared base labels; each runner's
`RUNNER_<N>_LABELS` adds runner-specific labels combined inside the
container by `entrypoint.sh` (mapped to `RUNNER_EXTRA_LABELS`). If you
prefer to bypass that pattern you can set `RUNNER_LABELS` directly in
the service environment instead.

## Security at a glance

- The GitHub App PEM is owned by **root** on the host (mode 600). Workflow
  jobs (UID 1001) cannot read it. See `docs/SECURITY-REVIEW-2026-04-20.md`
  finding **H-1** for the full analysis.
- Workflow jobs reach the Docker daemon through a `socket-proxy`
  sidecar that allows image cache operations only. `CONTAINERS` is
  intentionally disabled so jobs cannot inspect or exec into sibling
  runners. See `docs/SECURITY.md` and the socket-proxy block in
  `docker-compose.yml`.
- All Linux capabilities are dropped by default. Re-added: `CHOWN`,
  `DAC_OVERRIDE`, `FOWNER`, `SETGID`, `SETUID`, `KILL`. See the
  capability block in `docker-compose.yml` for the rationale.
- `no-new-privileges: true` prevents setuid-based privilege escalation
  inside the container.
- The runner is **ephemeral** — accepts exactly one job and exits. State
  is wiped between runs.

Report vulnerabilities privately — see [`SECURITY.md`](SECURITY.md).

## Operations

- `make build` — build the image (uses the digest-pinned base).
- `make up` / `make down` — lifecycle.
- `make logs` — tail every service.
- `make lint` — run the full pre-commit suite locally.
- `make audit` / `make audit-image` — checkov + trivy scans.

Day-2 details, scaling, and credential rotation: [`docs/OPERATIONS.md`](docs/OPERATIONS.md).

## License

MIT — see [`LICENSE.md`](LICENSE.md).
