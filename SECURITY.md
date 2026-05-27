# Security policy

## Reporting a vulnerability

If you believe you have found a security issue in this repository,
please disclose it privately. Do **not** open a public GitHub issue or
discussion.

**Preferred channel:** GitHub Private Vulnerability Reporting on this
repository — <https://github.com/ivuorinen/github-actions-runner-setup/security/advisories/new>.

If that is not available, email the maintainer at
**<ismo@ivuorinen.net>** with subject line `SECURITY: github-actions-runner-setup`.
Use PGP if you have it (key fingerprint on the maintainer's GitHub
profile).

Include:

- A description of the issue and its impact.
- A reproducer (commands, config, or PoC) that does not require
  privileged access beyond what an attacker would have.
- Affected commit SHA or release tag.
- Your suggested CVE category and severity, if applicable.

## What is in scope

- `scripts/entrypoint.sh`, `scripts/healthcheck.sh`
- `Dockerfile`
- `docker-compose.yml`
- `.claude/hooks/*.sh` (where they enforce trust boundaries)
- The token-exchange flow against the GitHub API
- The socket-proxy configuration

## What is out of scope

- Issues that require root on the Docker host (the operator already
  has equivalent capability).
- Vulnerabilities in the upstream `ghcr.io/actions/actions-runner` base
  image — report those at <https://github.com/actions/runner>.
- Vulnerabilities in `tecnativa/docker-socket-proxy` — report those at
  <https://github.com/Tecnativa/docker-socket-proxy>.
- Denial of service via legitimate workflow misuse (CI budget exhaustion,
  fork bombs) — `RUNNER_PIDS_LIMIT` and `RUNNER_MEM_LIMIT` are the
  defensive tuning surface.
- Malicious workflows running on the runners. This system explicitly
  treats workflow code as trusted (the only person who can push a
  workflow has merge rights). See `docs/SECURITY.md` "Threat model".

## Response timeline

- Acknowledgment within 72 hours.
- Initial assessment within 7 days.
- Coordinated disclosure on a timeline negotiated with the reporter,
  typically within 90 days of the initial report. Sooner if the issue
  is being actively exploited.

## Security review history

| Date | Review | Outcome |
|------|--------|---------|
| 2026-04-20 | Formal security review | 1 High (fixed), 3 Medium (2 fixed / 1 documented), 5 Low (4 fixed / 1 deferred). See `docs/SECURITY-REVIEW-2026-04-20.md`. |
| 2026-05-26 | Nitpicker adversarial audit | 1 Critical (fixed), multiple hardening additions. See `docs/audit/nitpicker-findings.md`. |
