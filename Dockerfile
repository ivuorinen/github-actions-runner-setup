# DL3002 (last USER should not be root) is ignored globally: the container
# intentionally ends with USER root so that entrypoint.sh can read the host
# PEM (owned by UID 0, mode 600) before dropping privileges via gosu. See
# docs/SECURITY-REVIEW-2026-04-20.md finding H-1. DL3008 (pin apt versions) is
# ignored because Debian point releases rotate package versions continuously;
# reproducibility comes from the digest-pinned base + Renovate rebuilds.
# hadolint global ignore=DL3002,DL3008

# Base image digest-pinned in addition to the semantic tag. Renovate manages
# both the tag and the digest — see .github/renovate.json.
FROM ghcr.io/actions/actions-runner:2.335.1@sha256:08c30b0a7105f64bddfc485d2487a22aa03932a791402393352fdf674bda2c29

# OCI image annotations. Renovate / GHCR / Trivy / Docker Hub all surface these.
# `revision` and `created` are stamped by the CI build via --label flags.
LABEL org.opencontainers.image.title="github-app-actions-runner" \
      org.opencontainers.image.description="Ephemeral GitHub Actions self-hosted runner with GitHub App authentication" \
      org.opencontainers.image.source="https://github.com/ivuorinen/github-actions-runner-setup" \
      org.opencontainers.image.documentation="https://github.com/ivuorinen/github-actions-runner-setup/blob/main/README.md" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="ivuorinen" \
      org.opencontainers.image.base.name="ghcr.io/actions/actions-runner:2.335.1"

# nosemgrep: dockerfile.security.last-user-is-root.last-user-is-root
USER root

# Notes on package selection:
#   - No docker packages: the base image already ships the docker CLI and
#     buildx plugin (static bundle installed to /usr/bin and
#     /usr/local/lib/docker/cli-plugins). Runners talk to the host daemon
#     via socket-proxy, so no daemon is needed in-container. The previously
#     installed docker.io pulled in dockerd/containerd/runc and their CVE
#     surface for a CLI we already had.
#   - tini handles PID 1 signal forwarding and reaping zombies.
#   - gosu drops privileges from root entrypoint to the runner user.
# dist-upgrade applies Ubuntu security updates published after the base
# image snapshot; Trivy flags every fixed-but-not-installed OS package.
# DL3005 (no dist-upgrade) predates that tradeoff and is ignored.
# hadolint ignore=DL3005,DL3008,DL3009
RUN apt-get update \
    && apt-get dist-upgrade -y \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        openssl \
        git \
        tini \
        gosu \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# The base image's static docker bundle includes daemon-side binaries that
# are never executed here (the daemon lives on the host, behind socket-proxy)
# but carry a large CVE surface. Remove them; keep the docker CLI and buildx
# plugin, which workflows use for pull/build through socket-proxy.
RUN rm -f /usr/bin/dockerd /usr/bin/docker-proxy /usr/bin/containerd \
    /usr/bin/containerd-shim-runc-v2 /usr/bin/ctr /usr/bin/runc

WORKDIR /home/runner

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh

# Lock down installed scripts: owned by root, world-readable, root-executable
# (gosu re-acquires the runner user shortly after entrypoint launches).
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh \
    && chown root:root /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh \
    && mkdir -p /runner-tmp /home/runner/_work \
    && usermod -aG docker runner \
    && chown -R runner:docker /home/runner /runner-tmp

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 CMD ["/usr/local/bin/healthcheck.sh"]

# Container entrypoint runs as root so that the host-side PEM can be owned
# by UID 0 (mode 600) and therefore unreadable by the runner user (UID 1001).
# entrypoint.sh reads the PEM, mints all GitHub App tokens in root-process
# memory, and then drops privileges via gosu before exec'ing config.sh and
# run.sh. Workflow jobs execute as the runner user and cannot read the PEM
# or ptrace the root bash parent under default kernel.yama.ptrace_scope=1.
# checkov:skip=CKV_DOCKER_8:Entrypoint must run as root to enforce H-1 PEM isolation; gosu drops privileges before user code executes.
# nosemgrep: dockerfile.security.last-user-is-root.last-user-is-root
USER root
