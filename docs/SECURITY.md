# Security model

This document describes the threat model and the defensive design choices
of the ephemeral runner system. For the formal security review with
findings and remediations, see `docs/SECURITY-REVIEW-2026-04-20.md`.

## Threat model

### Assets

| Asset | Why it matters |
|-------|----------------|
| GitHub App private key (PEM) | Mints installation tokens. Equivalent to GitHub App account takeover. |
| Installation access tokens (`ghs_*`) | 1-hour grant to perform App-scoped API operations. Can register/remove runners, read org runner state. |
| Runner registration tokens | 1-hour grant to register a new runner. Useful for impersonation attacks. |
| Workflow job context (env, secrets) | GitHub Actions secrets and OIDC tokens injected into the job. |
| Host Docker daemon | Trivially root-equivalent on the host. |
| Sibling runner containers' state | Could include in-flight job tokens, environment, code. |

### Trust boundaries

- **Operator → host**: assumed. The operator has root on the Docker host.
- **Host → runner container**: enforced by Docker namespaces.
- **Root entrypoint → runner user**: enforced by UID, mode 600 PEM,
  `no-new-privileges`, default `kernel.yama.ptrace_scope=1`.
- **Runner user → workflow job step**: NOT enforced — workflow code
  runs as the same UID as the runner listener. A malicious workflow
  step has full access to runner state.
- **Runner container → other runner container**: enforced by Docker
  namespacing AND by the socket-proxy denying `CONTAINERS` API calls.
- **Runner container → host Docker daemon**: mediated by the socket-proxy,
  which permits only image-cache operations.

### Adversaries

| Adversary | Capability assumed |
|-----------|---------------------|
| Hostile workflow author with PR access | Can submit arbitrary `.github/workflows/*.yml` to be reviewed; cannot bypass branch protection |
| Hostile workflow author with merge rights | Can run arbitrary code as the runner user UID 1001 |
| Compromised dependency (npm, pypi, docker image) | Equivalent to "workflow author with merge rights" once the workflow uses it |
| Network MITM | Mitigated by HTTPS; out of scope otherwise |
| Local user on Docker host (non-root) | Cannot read the PEM (mode 600 root) |
| Root on Docker host | Full compromise — out of scope (operator's responsibility) |

## Defenses

### Defense in depth, layered from outside in

1. **GitHub App permissions** are scoped narrowly:
   - Org: *Self-hosted runners read/write* + *Metadata read*
   - Repo: *Administration read/write* + *Metadata read*
   - No code-write, no contents:write, no secrets, no actions:write.

2. **Short-lived tokens.** Every token in the chain (JWT, installation,
   registration, remove) expires within an hour. Theft windows are
   bounded.

3. **PEM never enters the container env or `docker inspect` output.**
   It is bind-mounted as a file with restrictive host-side permissions.

4. **PEM is read only by root (UID 0).** The runner user cannot read it.
   See `docs/SECURITY-REVIEW-2026-04-20.md` finding **H-1**.

5. **Tokens are minted in root-process memory and dropped from the
   environment** before exec'ing into the runner user. See rule
   `.claude/rules/08-no-config-vars-leak-to-jobs.md`.

6. **`no-new-privileges` + `cap_drop: ALL`** with a minimal `cap_add`
   list. The runner user cannot regain root via setuid binaries and has
   only the capabilities listed in `docker-compose.yml`. See finding **M-2**.

7. **Docker socket is mediated by a proxy** that denies container
   inspection and exec. See finding **H-1** remediation and
   `.claude/rules/04-docker-socket-never-in-runner.md`.

8. **Ephemeral lifetime.** A runner accepts exactly one job and exits.
   Any state a malicious workflow plants is discarded with the
   container.

9. **Resource limits.** `mem_limit`, `cpus`, `pids_limit`, `ulimits` cap
   the blast radius of a runaway or hostile workflow.

10. **tmpfs `/runner-tmp` mode 0700.** Even sibling containers on the
    same volume cannot read it (they have separate mount namespaces; this
    is more about being explicit).

11. **CI lint suite enforces invariants.** Shellcheck, hadolint, checkov,
    actionlint, yamllint, markdownlint run on every push.

12. **Renovate keeps base images digest-pinned and current.**

13. **`.claude/hooks/*` block edits that would silently weaken the
    above.** See `.claude/rules/`. Specifically:
    - Rule 11 (`block-socket-proxy-widening.sh`) refuses
      `CONTAINERS=1` / `EXEC=1` / etc. on the socket-proxy without an
      explicit per-line allow annotation, preventing accidental
      re-enable of the cross-runner inspection surface.
    - Rule 12 (`block-runner-cap-widening.sh`) refuses adding caps
      beyond the documented minimum (CHOWN, DAC_OVERRIDE, FOWNER,
      SETGID, SETUID, KILL) — blocks SYS_PTRACE / SYS_ADMIN / NET_RAW
      / etc. from being slipped in.
    - Rule 13 (`block-dockerfile-broad-copy.sh`) refuses
      `COPY . .` / `ADD . …` / `ADD https://…` — a single
      `.dockerignore` mistake cannot ship secrets to image layers.

## What is explicitly NOT defended

- **Malicious workflow execution.** A workflow with permission to run on
  these runners has full code execution as the runner user. That is the
  point of self-hosted runners. The mitigation is process: only run
  trusted workflows on these runners. For PRs from untrusted forks, use
  GitHub-hosted runners or a separate restricted pool.
- **Side-channel attacks** (CPU caches, timing) between sibling runner
  containers on the same host. The threat model assumes the host is
  trusted; isolating side channels would require host-level mitigations
  (separate hosts, dedicated CPU sets) that are operator concerns.
- **Supply-chain attacks against the base image.** Trivy in CI catches
  some of these; Renovate keeps the digest current. There is no
  reproducible-build guarantee.
- **Egress filtering.** The runners can reach any IP the host's default
  route reaches. If you need outbound restriction, run a host-level
  firewall.

## Reporting a security issue

See `SECURITY.md` in the repository root for the disclosure process.

## Audit trail

- `docs/SECURITY-REVIEW-2026-04-20.md` — formal review, all findings
- `docs/audit/nitpicker-findings.md` — adversarial audit
  findings (regenerated by the `nitpicker` skill)
- `.claude/rules/` — invariants discovered during reviews; rules
  encode the *why* of each defensive choice
