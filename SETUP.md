# SETUP

This document describes how to set up the repository from zero and deploy it through Coolify.

## Prerequisites

- **Docker Engine** 20.10+
- **Docker Compose** v2.24+ (required for the `env_file: required: false` syntax in `docker-compose.yml`)

## 1. Create the GitHub App

Create a GitHub App owned by the organization if you want organization-level runners.

### Required permissions

For **organization-scoped runners**:

- Organization permissions:
  - **Self-hosted runners: Read and write**
  - **Metadata: Read-only**

For **repository-scoped runners**:

- Repository permissions:
  - **Administration: Read and write**
  - **Metadata: Read-only**

### App installation

Install the app to:

- the organization, if `RUNNER_SCOPE=org`
- the target repository or repositories, if `RUNNER_SCOPE=repo`

Record these values:

- **App ID**
- **Installation ID**
- **Private key PEM file**

## 2. Prepare the private key for environment-variable use

Linux:

```bash
base64 -w0 my-github-app.private-key.pem
```

macOS:

```bash
base64 -i my-github-app.private-key.pem | tr -d '\n'
```

Copy the resulting single-line base64 value.

## 3. Prepare the repository

Clone the repository and create the runtime environment file.

```bash
cp .env.example .env
```

Fill at least these values:

```dotenv
GITHUB_APP_ID=...
GITHUB_APP_INSTALLATION_ID=...
GITHUB_APP_PRIVATE_KEY_B64=...
RUNNER_SCOPE=org
GITHUB_ORG=your-org
RUNNER_GROUP=Default
```

For repository scope instead:

```dotenv
RUNNER_SCOPE=repo
GITHUB_REPO_OWNER=your-user-or-org
GITHUB_REPO_NAME=your-repo
```

## 4. Decide your labels

Example:

```dotenv
RUNNER_DEFAULT_LABELS=self-hosted,linux,x64,docker,ephemeral
RUNNER_1_LABELS=lint,small
RUNNER_2_LABELS=lint,medium
RUNNER_3_LABELS=general
```

Then use matching `runs-on` labels in workflows.

## 5. Local validation

Build and start locally:

```bash
docker compose build
docker compose up -d
```

Check logs:

```bash
docker compose logs -f runner-1
```

You should see the runner configure itself and go online in GitHub.

## 6. Deploy with Coolify

### Create the application

In Coolify:

1. Create a new application from this repository.
2. Select **Docker Compose** deployment.
3. Point it to the repository root.
4. Set the compose file path to `docker-compose.yml` if needed.

### Configure environment variables

In Coolify, set the same variables that exist in `.env.example`.

Minimum required values:

- `GITHUB_APP_ID`
- `GITHUB_APP_INSTALLATION_ID`
- `GITHUB_APP_PRIVATE_KEY_B64`
- `RUNNER_SCOPE`
- `GITHUB_ORG` or `GITHUB_REPO_OWNER` + `GITHUB_REPO_NAME`

### Host Docker socket

This repository mounts:

```yaml
- /var/run/docker.sock:/var/run/docker.sock
```

Your Coolify Docker host must allow this mount. Without it, shared Docker image cache will not work, and container-based jobs that depend on host Docker will fail.

## 7. Verify runner visibility in GitHub

### For organization scope

Go to:

- Organization Settings
- Actions
- Runners

### For repository scope

Go to:

- Repository Settings
- Actions
- Runners

You should see each runner appear with its labels.

## 8. Example workflow

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

## 9. Add more runners

To add a new runner:

1. copy one `runner-*` service block in `docker-compose.yml`
2. rename it, for example `runner-4`
3. set its hostname
4. set `RUNNER_INSTANCE_NAME`
5. set `RUNNER_DEFAULT_LABELS` (shared base) and add a per-runner extra-label variable (e.g. `RUNNER_4_LABELS`) mapped to `RUNNER_EXTRA_LABELS`
6. optionally add matching `RUNNER_4_LABELS` and `RUNNER_4_NAME` variables to `.env`

If you prefer, you can also set `RUNNER_LABELS` directly in the service instead of using the `RUNNER_DEFAULT_LABELS` + `RUNNER_EXTRA_LABELS` pattern.

Example additional service:

```yaml
  runner-4:
    <<: *runner-common
    hostname: ${RUNNER_CONTAINER_PREFIX:-gha-runner}-4
    environment:
      GITHUB_APP_ID: ${GITHUB_APP_ID}
      GITHUB_APP_INSTALLATION_ID: ${GITHUB_APP_INSTALLATION_ID}
      GITHUB_APP_PRIVATE_KEY_B64: ${GITHUB_APP_PRIVATE_KEY_B64:-}
      GITHUB_APP_PRIVATE_KEY_FILE: ${GITHUB_APP_PRIVATE_KEY_FILE:-}
      GITHUB_HOST: ${GITHUB_HOST:-github.com}
      GITHUB_API_URL: ${GITHUB_API_URL:-https://api.github.com}
      GITHUB_WEB_URL: ${GITHUB_WEB_URL:-https://github.com}
      RUNNER_SCOPE: ${RUNNER_SCOPE:-org}
      GITHUB_ORG: ${GITHUB_ORG:-}
      GITHUB_REPO_OWNER: ${GITHUB_REPO_OWNER:-}
      GITHUB_REPO_NAME: ${GITHUB_REPO_NAME:-}
      RUNNER_GROUP: ${RUNNER_GROUP:-Default}
      RUNNER_WORKDIR: ${RUNNER_WORKDIR:-/home/runner/_work}
      UNSET_CONFIG_VARS: ${UNSET_CONFIG_VARS:-true}
      RUNNER_INSTANCE_NAME: ${RUNNER_4_NAME:-}
      RUNNER_DEFAULT_LABELS: ${RUNNER_DEFAULT_LABELS:-self-hosted,linux,x64,docker,ephemeral}
      RUNNER_EXTRA_LABELS: ${RUNNER_4_LABELS:-lint,large}
```

And in `.env`:

```dotenv
RUNNER_4_LABELS=lint,large
RUNNER_4_NAME=
```

## 10. Operational notes

- These runners are **ephemeral** by design.
- Job workspace should not be persisted across runs.
- Docker image caching is shared through the host daemon.
- Any workflow that can reach the Docker socket has effectively elevated control over the runner host, so only trusted workflows should target these runners.
- For pull requests from untrusted forks, use separate restricted runners or GitHub-hosted runners.

## 11. Troubleshooting

### Runner does not show up

Check:

- app permissions
- installation target
- installation ID
- app ID
- private key base64 value
- org or repo names

Then inspect logs:

```bash
docker compose logs -f runner-1
```

### Jobs stay queued

Check that workflow `runs-on` labels exactly match the labels configured for at least one runner.

### Docker commands fail inside jobs

Check that the Docker socket mount is present and that the host daemon is running.

If the socket is present but jobs still get `permission denied`, the container's
`docker` group GID does not match the host socket GID.  Fix:

```bash
# Find the host socket GID
stat -c '%g' /var/run/docker.sock
```

Set that value as `DOCKER_GID` in your `.env` (or as a Coolify environment variable).
The `group_add` entry in `docker-compose.yml` will add the runner process to that
supplementary group at startup.  The entrypoint logs a warning with the correct GID
if the socket is inaccessible at startup.

### Coolify deployment succeeds but runners are offline

Check whether Coolify allows mounting `/var/run/docker.sock` for this app and whether the environment variables were injected correctly.
