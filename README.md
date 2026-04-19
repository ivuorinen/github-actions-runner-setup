# Self-hosted GitHub Actions runners for Coolify

This repository provides ephemeral self-hosted GitHub Actions runners using a GitHub App for registration.

## Features

- GitHub App authentication
- Ephemeral runners
- Shared Docker image cache via host Docker socket
- Docker Compose deployment
- Easy extension by copying runner service blocks
- Compatible with Coolify-style Docker Compose deployments

## How it works

Each runner container:

1. creates a GitHub App JWT
2. exchanges it for an installation token
3. requests a short-lived runner registration token
4. registers itself as an ephemeral runner
5. executes one job
6. de-registers itself on shutdown
7. restarts as a fresh container through Docker restart policy

## Shared image cache

All runners mount:

- `/var/run/docker.sock:/var/run/docker.sock`

This means Docker pulls and image layers are shared through the host daemon.
If your workflows repeatedly use the same container images for linters, scanners, or build tools, later jobs avoid re-pulling unchanged layers.

## Requirements

- Docker Engine 20.10+
- Docker Compose v2.24+ (required for `env_file: required: false` support)

## Security

### Docker socket proxy

Runners connect to the Docker daemon through a `socket-proxy` sidecar service
(`tecnativa/docker-socket-proxy`). Runner containers do not hold the host
socket directly — `DOCKER_HOST` is set to the proxy's TCP endpoint instead.
This prevents workflow jobs from using the raw socket to inspect sibling
runner containers or bind-mount the host filesystem.

Note: the proxy still permits `--privileged` container creation if a job
explicitly requests it. Full elimination of that vector requires rootless Docker
on the host. Ensure only trusted workflows target these runners — see the
operational notes in `SETUP.md`.

### GitHub App private key

Prefer `GITHUB_APP_PRIVATE_KEY_FILE` (a file mounted into the container) over
`GITHUB_APP_PRIVATE_KEY_B64`. The base64 env var is stored in Docker's
container config and is readable via `docker inspect` for the lifetime of the
container. The `GITHUB_APP_PRIVATE_KEY_FILE` path is not stored in the
container config. When `GITHUB_APP_PRIVATE_KEY_B64` is used, the runner logs a
warning at startup.

## Quick start

1. Copy `.env.example` to `.env`
2. Fill in GitHub App values
3. Set `RUNNER_SCOPE=org` or `RUNNER_SCOPE=repo`
4. Deploy with Docker Compose or through Coolify
5. Target these runners in workflows using their labels

## Example workflow labels

For `runner-1` with:

- `RUNNER_DEFAULT_LABELS=self-hosted,linux,x64,docker,ephemeral`
- `RUNNER_1_LABELS=lint,small`

Use:

```yaml
runs-on: [self-hosted, linux, x64, docker, ephemeral, lint, small]
```

## Adding more runners

Copy one existing `runner-*` service in `docker-compose.yml` and change:

- service name
- hostname
- `RUNNER_INSTANCE_NAME`
- the per-runner label variable (e.g. `RUNNER_1_LABELS`, `RUNNER_2_LABELS`, …)

`RUNNER_DEFAULT_LABELS` provides the shared base labels applied to every runner, and each runner's
`RUNNER_<N>_LABELS` adds runner-specific labels (mapped to `RUNNER_EXTRA_LABELS` inside the container).
If you prefer to bypass that pattern you can set `RUNNER_LABELS` directly in the service environment instead.

See `SETUP.md` for the complete setup flow.
