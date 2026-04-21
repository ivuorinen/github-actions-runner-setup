# DL3002 (last USER should not be root) is ignored globally: the container
# intentionally ends with USER root so that entrypoint.sh can read the host
# PEM (owned by UID 0, mode 600) before dropping privileges via gosu. See
# docs/SECURITY-REVIEW-2026-04-20.md finding H-1. DL3008 (pin apt versions) is
# ignored because Debian point releases rotate package versions continuously;
# reproducibility comes from the digest-pinned base + Renovate rebuilds.
# hadolint global ignore=DL3002,DL3008

# Base image digest-pinned in addition to the semantic tag. Renovate manages
# both the tag and the digest — see .github/renovate.json.
FROM ghcr.io/actions/actions-runner:2.334.0@sha256:b6614fce332517f74d0a76e7c762fb08e4f2ff13dcf333183397c8a5725b6e8e

# nosemgrep: dockerfile.security.last-user-is-root.last-user-is-root
USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
        openssl \
        git \
        docker.io \
        tini \
        gosu \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /home/runner

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh \
    && mkdir -p /runner-tmp /home/runner/_work \
    && usermod -aG docker runner \
    && chown -R runner:docker /home/runner /runner-tmp

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 CMD ["/usr/local/bin/healthcheck.sh"]

# Container entrypoint runs as root so that the host-side PEM can be owned
# by UID 0 (mode 600) and therefore unreadable by the runner user (UID 1001).
# entrypoint.sh reads the PEM, mints all GitHub App tokens in root-process
# memory, and then drops privileges via gosu before exec'ing config.sh and
# run.sh. Workflow jobs execute as the runner user and cannot read the PEM
# or ptrace the root bash parent under default kernel.yama.ptrace_scope=1.
# checkov:skip=CKV_DOCKER_8:Entrypoint must run as root to enforce H-1 PEM isolation; gosu drops privileges before user code executes.
# nosemgrep: dockerfile.security.last-user-is-root.last-user-is-root
USER root
