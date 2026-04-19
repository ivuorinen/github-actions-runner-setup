# Self-hosted GitHub Actions runners for Coolify

This repository provides ephemeral self-hosted GitHub Actions runners using a GitHub App for registration.

## Features

- GitHub App authentication
- Ephemeral runners
- Shared Docker image cache via socket-proxy sidecar
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

All runners connect to Docker through the `socket-proxy` sidecar, which in turn
mounts the host socket. Docker pulls and image layers are shared through the host
daemon — if your workflows repeatedly use the same container images, later jobs
avoid re-pulling unchanged layers.

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

Note: the proxy allows `docker build` and `docker pull` but disables container
creation and inspection (`CONTAINERS` is not enabled). This blocks `docker run`
and prevents jobs from inspecting sibling runner containers. If jobs need
`docker run`, add `CONTAINERS: 1` to the socket-proxy environment and note
that this re-enables cross-runner container inspection. Ensure only trusted
workflows target these runners — see the operational notes in `SETUP.md`.

### GitHub App private key

Set `GITHUB_APP_PRIVATE_KEY_HOST_PATH` to the absolute path of the PEM file
on the Docker host. `docker-compose.yml` bind-mounts it read-only into every
runner container at `/run/secrets/github_app_key`. `entrypoint.sh` copies it
to a private tmpfs and deletes it before the runner starts accepting jobs —
the key material is never stored in the container config and never appears in
`docker inspect` output.

## Quick start

1. Copy the GitHub App PEM to the host: `cp my-app.pem /etc/github-app/private-key.pem && chmod 600 /etc/github-app/private-key.pem`
2. Copy `.env.example` to `.env`
3. Fill in `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, `GITHUB_APP_PRIVATE_KEY_HOST_PATH`, and `RUNNER_SCOPE`
4. Set `RUNNER_SCOPE=org` (and `GITHUB_ORG`) or `RUNNER_SCOPE=repo` (and `GITHUB_REPO_OWNER`/`GITHUB_REPO_NAME`)
5. Run `docker compose up -d`
6. Target these runners in workflows using their labels

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
