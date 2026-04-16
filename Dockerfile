FROM ghcr.io/actions/actions-runner:2.333.1

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

USER runner
