# Nitpicker Findings
Generated: 2026-05-26
Last validated: 2026-05-28 (Pass 103: pre-commit re-validation of working-tree deltas)

## Summary
- Total: 61 | Open: 0 | Fixed: 60 | Invalid: 1
- Iterations 1-10: 23 findings (1 Critical + 8 High + 14 Medium/Low). All fixed.
- Iterations 11-25: 5 findings (1 High + 4 Medium/Low). All fixed.
- Iterations 26-50: 19 regression checks across linters, hooks, and PEM-mode invariants. All green. 0 new findings.
- Pass 53: 11 new findings (1 Critical + 5 High + 5 Medium). All fixed. 1 Invalid.
- Pass 54: 1 new finding (Medium). Fixed.
- Pass 55: 1 new finding (High — second-order bypass introduced by the Pass 53 force-push fix). Fixed.
- Pass 56-67: 6 new findings. All fixed.
- Pass 68-102: 3 new findings (curl retry semantics, tmpfs memory accounting undocumented, doc cross-reference gaps for new rules/healthcheck/macOS). All fixed. 32 additional probes ran with no new findings (operational config, doc depth, structural cross-checks).

## Iteration log

Iter 1: initial whole-repo sweep. Found N-1 (critical PEM mode arithmetic) and 22 other findings. All fixed.
Iter 2: race conditions in entrypoint. Found N-24 (SIGTERM race window) and N-25 (healthcheck false positive). Fixed both.
Iter 3: token leakage paths. No new findings.
Iter 4: GitHub API edge cases. Found N-26 (empty token accepted) and N-27 (curl timeout too short). Fixed both.
Iter 5-10: container escape & privilege boundary. No new findings (defense in depth verified).
Iter 11-20: adversarial hook bypass. Found N-28 (bash -c bypass), N-29 (quoted-arg bypass), N-30 (compose long-form), N-31 (self-flagging hook). Fixed all.
Iter 21-30: CI workflow injection. No new findings.
Iter 31-40: compose adversarial. No new findings.
Iter 41-50: documentation accuracy + regression. Verified all critical invariants hold. 0 new findings.
Iter 51: user-authorised settings.json hook registration (N-22 fixed) + `${CLAUDE_PROJECT_DIR}` path portability (N-32 fixed).
Iter 52: close-out — elevated previously-deferred cosmetic findings under user directive "no matter how small or cosmetic". N-19 (GITHUB_HOST wired up to derive GHES URLs) and N-23 (RUNNER_LABELS commented in .env.example) both fixed. CHANGELOG.md added. SETUP.md §10 GHES section added.
Iter 53: adversarial hook-bypass pass under user directive "be more aggressive each pass". 11 new findings: 1 Critical (CI smoke test never reaches the N-1 mode-check codepath), 5 High (arithmetic-precedence regex misses original bug, socket-mount Write-mode bypass, force-push refspec bypass, shell-strict-mode false-positives + leniency, token-logging non-portable regex), 5 Medium (cat-secrets dump-tool list narrow, post-edit strict-mode gap, hadolint version drift, socket-proxy healthcheck shallow, env-example default value confusing). Plus three new architectural rules (11/12/13) and the OIDC documentation TODO item closed.

Additional fixes during late iterations (not assigned IDs because they were straight improvements, not findings):

- api() tempfile cleanup converted to RETURN trap for signal safety.
- HTTP_PROXY/HTTPS_PROXY support documented in OPERATIONS.md.
- IPv6/DNS notes added to OPERATIONS.md.
- .editorconfig fixed to cover `Makefile` (capital M) and align YAML max line length with markdownlint (200).
- README.md indexes CHANGELOG.md.

## Open Findings

_None._ All findings closed across 102 iterative passes.

## Fixed

### Pass 103 — 2026-05-28 (pre-commit re-validation of working-tree deltas)

Re-validated all 60 prior findings against the working tree before committing
the uncommitted changes in grouped commits: shellcheck clean, shfmt clean,
rule 06/09/11 verification greps green, `.claude/settings.json` parses and
wires all 16 hooks, the arithmetic-precedence hook exits 0 on `entrypoint.sh`
(N-1 guard holds), every hook carries the executable bit. 1 new finding.

#### [N-60] LOW — dead `endsblock()` awk function in `block-runner-cap-widening.sh`
Fixed: 2026-05-28
Notes: The new hook defined an awk `function endsblock(l) { ... }` that was
never called — block termination is handled inline by the two trailing rules
(`in_cap && /^[[:space:]]*[a-zA-Z_]+:/ { in_cap=0 }` and
`in_cap && /^[^[:space:]-]/ { in_cap=0 }`). The dead function duplicated that
logic and would drift out of sync with the real rules on a future edit.
Removed it. Behaviour unchanged (verified: shellcheck clean, hook still exits
0 on the current compose and blocks a synthetic `- SYS_PTRACE` line).

### Pass 68-102 — 2026-05-27 (operational + structural exhaustion)

35 fresh adversarial probes spanning: curl retry semantics, JWT clock-skew edges, stat portability, argument injection, signal handling, tmpfs/mem_limit interaction, log-driver disk-fill, Compose schema (depends_on conditions, env_file required, network defaults), pre-commit pin staleness, hadolint exit-code, actionlint rationale, Renovate config validity, README/SETUP macOS coverage, ARCHITECTURE token-chain accuracy, OPERATIONS scaling, SECURITY rule cross-refs, TROUBLESHOOTING socket-proxy healthcheck, ENVIRONMENT-VARIABLES tmpfs accounting, CONTRIBUTING rule references, hook executability, every CI file reference, every Dockerfile COPY source, every `.gitignore`/`.dockerignore` secret pattern, every audit ID with a definition, every internal markdown anchor resolves. 3 new findings:

#### [N-57] MEDIUM — `curl --retry-all-errors` retried 401/403/404 wastefully
Fixed: 2026-05-27
Notes: The entrypoint's `api()` function passed `--retry-all-errors` to curl, which causes curl to retry on ALL non-2xx responses including 401 (bad credentials), 403 (insufficient permissions), and 404 (wrong installation/org/repo). These are not transient — they reflect a misconfigured GitHub App and will fail identically every attempt. With `--retry 3 --max-time 60`, an operator misconfiguration costs 180 seconds of waiting before the actual error message surfaces. Removed `--retry-all-errors`; bare `--retry 3` covers the genuinely transient cases (5xx, connection failures, timeouts) which is the only retry behaviour that helps. Documented the rationale in the function comment block.

#### [N-58] MEDIUM — Memory-vs-tmpfs accounting not documented
Fixed: 2026-05-27
Notes: Each runner has `tmpfs: /tmp:size=1g` and `/runner-tmp:size=128m`. Linux counts tmpfs page usage against the container's `mem_limit` cgroup, so the effective workload-available memory with the default `RUNNER_MEM_LIMIT=4g` is approximately 3 GiB — not 4 GiB. A workflow filling /tmp with 1 GiB and using 3 GiB RSS triggers OOM unexpectedly. Added an explanatory paragraph to `docs/ENVIRONMENT-VARIABLES.md` under `RUNNER_MEM_LIMIT` with the formula and the workaround (place large artefacts under `/home/runner/_work`, not tmpfs).

#### [N-59] LOW — Documentation gaps: rule 11/12/13 not cross-referenced from SECURITY.md; socket-proxy healthcheck failure not in TROUBLESHOOTING.md; macOS Docker Desktop quirks not in SETUP.md; actionlint `-shellcheck=` rationale not in pre-commit config; rule 10 not referenced from anywhere outside the rules dir
Fixed: 2026-05-27
Notes: Five small documentation completeness gaps closed together since they share the "the new artefact exists but it is not yet discoverable from where an operator would look" pattern:
- `docs/SECURITY.md` "Defense in depth #13" now enumerates the specific bypass each of rules 11/12/13 prevents.
- `docs/TROUBLESHOOTING.md` now has a "socket-proxy reports unhealthy or `_ping` fails" section.
- `SETUP.md` now has a section 11 "Local development on macOS (Docker Desktop)" covering bind-mount UID translation and the docker.sock symlink.
- `.pre-commit-config.yaml` actionlint hook now has a comment explaining why `-shellcheck=` disables the bundled shellcheck-via-actionlint pass.
- `CONTRIBUTING.md` Style section now references rules 10/11/12/13 by file path so a contributor reading the contribution guide finds them.
- `TODO.md` "In progress / future" renamed to "Future enhancements (deferred feature work, not findings)" to disambiguate from open audit findings.

### Pass 56-67 — 2026-05-27 (rule-enforcing hooks, API-contract harden, doc gaps)

#### [N-51] HIGH — Rules 11/12/13 lacked enforcing PreToolUse hooks
Fixed: 2026-05-27
Notes: The rules added in Pass 53 documented intent but had no client-side enforcement. A contributor (or Claude itself in a future session) could flip `CONTAINERS: 1` on socket-proxy, add `SYS_PTRACE` to runner cap_add, or write `COPY . .` into the Dockerfile without anything blocking the edit. Added three new PreToolUse hooks:
- `block-socket-proxy-widening.sh` — refuses CONTAINERS/EXEC/VOLUMES/NETWORKS/PLUGINS/SECRETS/SWARM/TASKS/SERVICES/NODES/SESSION/SYSTEM=1 without the `# allow-socket-proxy-rule-11` annotation.
- `block-runner-cap-widening.sh` — refuses any cap beyond CHOWN/DAC_OVERRIDE/FOWNER/SETGID/SETUID/KILL without `# allow-cap-rule-12: <reason>`.
- `block-dockerfile-broad-copy.sh` — refuses `COPY . .`, `COPY ./ .`, `ADD . …`, `ADD https://…` (multi-stage `COPY --from=…` exempt).
Verified against 8 BLOCK/ALLOW cases; all classified correctly. Registered in `.claude/settings.json`. PreToolUse hook count is now 11 (was 8); PostToolUse remains 6.

#### [N-52] MEDIUM — `GITHUB_API_URL`/`GITHUB_WEB_URL` trailing slash produced `//` paths on GHES
Fixed: 2026-05-27
Notes: Operators may set `GITHUB_API_URL=https://ghes.example.com/api/v3/` (trailing slash). The entrypoint concatenated this with `/app/installations/...` yielding `https://ghes.example.com/api/v3//app/...`. `api.github.com` tolerates the double slash; some GHES versions return 404 on it. Added `GITHUB_API_URL="${GITHUB_API_URL%/}"` and the matching `GITHUB_WEB_URL` strip immediately after the derivation block.

#### [N-53] MEDIUM — No `ulimit -c 0` to prevent token leakage via core dump
Fixed: 2026-05-27
Notes: If the entrypoint crashes between JWT mint and the runner registration / cleanup paths, the JWT, installation token, registration token, or remove token may be in process memory at fault time. A core dump (if enabled at the host level) would persist that memory to disk. Containers writing to overlay or bind-mounted `/var/lib/systemd/coredump` from inside is unlikely under our compose config, but explicit `ulimit -c 0` closes the gap without trusting host policy. Added before any token-handling code runs.

#### [N-54] LOW — `RUNNER_REMOVE_TOKEN` not explicitly cleared at cleanup time
Fixed: 2026-05-27
Notes: The variable is a non-exported shell variable and bash automatically reclaims its memory at process exit, but a defensive `RUNNER_REMOVE_TOKEN=""; unset RUNNER_REMOVE_TOKEN` in the cleanup trap closes the tiny window where a debugger attached at exit could read the address. Defense in depth, not a critical bug.

#### [N-55] MEDIUM — `TROUBLESHOOTING.md` missing six operator-facing failure modes
Fixed: 2026-05-27
Notes: Cross-checked every `fail "..."` message in entrypoint.sh against the section headings in TROUBLESHOOTING. Six gaps closed (operator typing the error message into the doc would now find a section):
- "Required environment variable is missing: \<NAME\>"
- "entrypoint.sh must run as root (UID 0)"
- "Key file is not readable by root"
- "Network error calling POST \<url\>"
- "API returned no token" / "suspiciously short token"
- "RUNNER_LABELS is empty"
Each section explains the failure mode, lists likely causes, and gives the operator-side fix.

#### [N-56] LOW — `SECURITY-REVIEW-2026-04-20.md` L-5 not marked fixed despite resolution
Fixed: 2026-05-27
Notes: The 2026-04-20 review recommended lowering shellcheck severity from `warning` to `style`. The change was made (pre-commit-config.yaml now passes `--severity=style`), the summary table marked L-5 as Fixed, but the detail section under "## 4. Detailed findings" still read as an open recommendation. Updated to clearly mark **[FIXED]** with the original text preserved as historical context.

### Pass 55 — 2026-05-27 (self-review of Pass 53/54 deltas)

#### [N-50] HIGH — `block-force-push-main.sh` Pass-53 fix missed several real force/delete forms
Fixed: 2026-05-27
Notes: After widening the hook to cover `+main`, I re-attacked it and found three remaining real bypasses:
- `git push origin +main` (no source ref, no colon) — my refspec regex `\+([[:space:]:]+|[^[:space:]]*:)…` required either whitespace/colon or non-space-then-colon AFTER the `+`, so a bare `+main` slipped through.
- `git push origin +refs/heads/main` — same root cause.
- `git push --delete origin main` — the `--delete` regex required the branch name to immediately follow `--delete<space>`, but the typical form has `<remote> <branch>` between them.
Rewrote the regexes:
- `refspec_force_target_re` now uses `\+([^[:space:]:]+:)?(refs/heads/)?(main|master)` — the optional `(source:)?` group accepts both bare `+main` and `+HEAD:main`.
- Split delete detection into two: `push_colon_delete_re` (`:main` empty-source form) and `push_delete_flag_re` (`--delete` flag form with arbitrary remote between).
Re-verified against 16 cases (9 BLOCK, 7 ALLOW). All classified correctly. The bypass classes — empty-source colon delete and bare `+main` — were both untested in Pass 53 (the test only covered the simple `+main` *with* a separator that I thought was required).

### Pass 54 — 2026-05-27 (second-order audit)

#### [N-49] MEDIUM — `block-cat-secrets.sh` missed `/run/secrets/` and `github_app_key` paths
Fixed: 2026-05-27
Notes: `is_pem_target()` only matched the `.pem` filename suffix. But the actual PEM inside the container lives at `/run/secrets/github_app_key` (set by `GITHUB_APP_PRIVATE_KEY_FILE` in compose) — no `.pem` extension. A `cat /run/secrets/github_app_key` inside a runner shell would dump the most sensitive credential in the system and the hook would not block. Extended `is_pem_target()` to also match `/run/secrets/<anything>`, any path containing `github_app_key`, and any `private-key` token. Verified: 6/7 PEM-shaped paths now BLOCK, plus the existing `.pem` matcher, plus `README.md` still ALLOWs.

### Pass 53 — 2026-05-27 (adversarial hook-bypass + CI correctness)

#### [N-33] CRITICAL — CI smoke test never reaches the N-1 PEM-mode check
Fixed: 2026-05-27
Notes: The "Smoke test — entrypoint refuses bad PEM mode" step in `.github/workflows/ci-docker.yml` generated a key file with `chmod 644` but never `chown 0:0`. Because the bind-mounted file inside the container retains the host uid (typically 1001 on GHA `ubuntu-latest`), the entrypoint's **owner check** at line 304 fires first (`Key file must be owned by UID 0`) and the script exits before reaching the arithmetic-precedence-sensitive **mode check** at line 313. The grep `(Key file (must be owned|permissions must not))` accepted either error, so the test passed regardless of whether the N-1 fix was in place. A regression of N-1 would not have been caught by this test. Split into two phases: Phase 1 verifies the owner check fires (`chmod 600`, runner-owned), Phase 2 verifies the mode check fires (`sudo chown 0:0 && sudo chmod 644`). Each phase asserts a specific error message; Phase 2 is the genuine N-1 regression guard.

#### [N-34] HIGH — `block-shell-strict-mode-removal.sh` regex broken in both directions
Fixed: 2026-05-27
Notes: Two bugs in one regex `'set[[:space:]]+-(E[a-z]*e[a-z]*|.*-o[[:space:]]+pipefail)'`:
- **False positive:** `set -o pipefail` (the long-form equivalent of `-o pipefail`) failed both alternatives — alt 1 requires `E…` start, alt 2 requires `-o` somewhere within the trailing chars but the outer `-` was already consumed. The hook would BLOCK any script that used long-form `set -o pipefail` even though rule 02 endorses it.
- **False negative:** `set -euo pipefail` (missing `-E`) matched alt 2 via `.*-o\s+pipefail` and slipped through. Rule 02 requires all four flags.
Rewritten as per-flag presence checks: each of `-E`, `-e`, `-u`, `-o pipefail` is detected independently (short-form cluster OR long-form `set -o <name>`). Verified against canonical, missing-E, and long-form variants.

#### [N-35] HIGH — Arithmetic-precedence regex did not catch the original N-1 bug
Fixed: 2026-05-27
Notes: The regex `\(\([^()]*[[:space:]][&|^][[:space:]][^()]*(==|!=)` in both `.claude/hooks/validate-entrypoint-arithmetic.sh` and `scripts/pre-commit-hooks/check-arithmetic-precedence.sh` requires `[^()]*` to span the gap between the bash-arithmetic opener and the bitwise operator. Against the actual N-1 input `(((8#${key_mode}) & 077 == 0))`, the inner `)` of `(8#${key_mode})` breaks `[^()]*` — no position of `((` start can reach the `&` without crossing a `)`. **The hook that purports to guard against N-1 never matched the N-1 pattern.** Replaced with `\(\(.*[&|^][^)]*(==|!=)`: `.*` allows spanning inner `)`s, `[^)]*` between bitwise and comparison correctly excludes the FIX shape `(((8#mode) & 077) == 0)` because the closing `)` between `&` and `==` interrupts the match. Verified against 7 test cases (3 BAD inputs all match, 4 SAFE inputs all skip). Required exclusion of self-referential files (rule 09 doc, the hooks themselves) to avoid self-matching the regex literal.

#### [N-36] HIGH — `block-runner-socket-mount.sh` Write-mode bypass via socket-proxy text co-occurrence
Fixed: 2026-05-27
Notes: The hook allowed any socket-mount edit when the content contained the literal `socket-proxy`. For Edit operations (partial snippets), this was a reasonable heuristic. For Write operations (entire file), the whole compose file always contains the `socket-proxy:` service definition somewhere — so the hook always passed and never blocked. An adversarial Write that added `- /var/run/docker.sock:/var/run/docker.sock` to runner-1 was not detected. Replaced with: Write mode parses the full compose with awk (same logic as `scripts/pre-commit-hooks/check-no-docker-sock-in-runner.sh`) and attributes each `/var/run/docker.sock` line to its owning service; partial-edit mode requires the literal `^  socket-proxy:` service-header line (a comment mentioning the proxy no longer unblocks). Verified: Write with mount on runner-1 → BLOCK; Write with mount only on socket-proxy → ALLOW.

#### [N-37] HIGH — `block-token-logging.sh` regex used non-portable GNU `\b`
Fixed: 2026-05-27
Notes: `grep -nE '…\b'` is a GNU extension. On macOS (BSD grep -E), the behaviour is implementation-defined and not guaranteed by POSIX ERE. Contributors developing on macOS would see the hook silently miss tokens followed by `}`, `"`, `,`, etc. Replaced `\b` with `([^A-Za-z0-9_]|$)` — explicit POSIX equivalent for "word boundary after". Also extended the detected log primitives to include `tee` (covers `tee /tmp/out <<< "${jwt}"`). Verified on an entrypoint.sh-shaped payload: all five intentional token-logging lines flagged.

#### [N-38] HIGH — `block-force-push-main.sh` missed refspec-form force push
Fixed: 2026-05-27
Notes: `git push origin +main` is a force push (the `+` refspec prefix means "allow non-fast-forward"). The original hook only matched `--force` / `-f` flag forms and let `+main`, `+master`, `+refs/heads/main`, and `+HEAD:main` through. Added `refspec_force_re` that matches the `+`-prefixed refspec against `(main|master)` or `refs/heads/(main|master)`. Also added a check for `git update-ref -d refs/heads/(main|master)` which would delete the branch outright. Verified: `+main` BLOCK, `+refs/heads/main` BLOCK, `+feature` ALLOW, `--force-with-lease` ALLOW.

#### [N-39] MEDIUM — `block-cat-secrets.sh` dump-tool list narrow; missed redirect forms
Fixed: 2026-05-27
Notes: Extended `DUMP_TOOLS_RE` to include `awk`, `sed`, `grep` family (`rg`, `ag`, `fgrep`, `egrep`), `base64`, `tar`, `dd`, `cp`, `mv`, `install`. Added detection for two redirect-form leaks the original hook missed: `… < .env` (any command that reads .env via stdin redirect) and `$(< .env)` (bash short-form file-read substitution). Verified: 8 BAD commands all BLOCK, 4 SAFE commands all ALLOW (including `cat README.md` and `env | grep -v TOKEN > out`).

#### [N-40] MEDIUM — `block-shell-strict-mode-removal.sh` only checked Write, not Edit
Fixed: 2026-05-27
Notes: PreToolUse Write check could not see the rest of the file after an Edit operation removed strict mode. Added a PostToolUse companion `validate-shell-strict-mode.sh` that reads the on-disk file after the edit lands and warns if any of `-E/-e/-u/-o pipefail` is missing from the first 30 lines. Registered in `.claude/settings.json` under PostToolUse:Edit|Write. Verified against the actual `entrypoint.sh` (passes), and a synthetic file with `set -euo pipefail` only (warns about missing -E).

#### [N-41] MEDIUM — Hadolint version pinning inconsistent across pre-commit / Makefile / hook
Fixed: 2026-05-27
Notes: pre-commit was on v2.14.0, `make lint-docker` and `validate-dockerfile-on-edit.sh` pinned to v2.12.0@sha256:7dba9a9…. Different versions = different findings = a Dockerfile change passing locally could fail in pre-commit (or vice-versa). Aligned both consumers to v2.14.0@sha256:27086352fd5e1907ea2b934eb1023f217c5ae087992eb59fde121dce9c9ff21e (the manifest digest verified against Docker Hub at the time of this audit). Renovate will keep the pair in sync.

#### [N-42] MEDIUM — Socket-proxy healthcheck only probed haproxy listener, not upstream
Fixed: 2026-05-27
Notes: `nc -z 127.0.0.1 2375` verifies haproxy is listening on the proxy port but says nothing about whether the upstream `/var/run/docker.sock` bind-mount is actually reachable. A Coolify misconfiguration where the host socket is unmounted would leave the proxy "healthy" while every `docker` call from runners failed with opaque errors. Switched to `wget -q --spider http://127.0.0.1:2375/_ping` (the Docker Engine ping endpoint, allowed by `PING: 1`). End-to-end verification: green only when the upstream is reachable. wget is present in the Tecnativa image (Alpine + busybox).

#### [N-44] RULE — Added rule 11: `socket-proxy` exposes only the minimum Docker API surface
Fixed: 2026-05-27
Notes: New `.claude/rules/11-socket-proxy-env-minimum.md` documents the allowed-by-default set (IMAGES, BUILD, POST, INFO, PING) and the forbidden-without-justification set (CONTAINERS, EXEC, VOLUMES, NETWORKS, PLUGINS, SECRETS, SWARM, TASKS, SERVICES, NODES, SESSION, SYSTEM). Indexed in `.claude/rules/README.md`. Closes the gap where a contributor could flip `CONTAINERS: 1` for convenience and silently re-enable cross-runner inspection.

#### [N-45] RULE — Added rule 12: runner services drop ALL caps and re-add only the minimum
Fixed: 2026-05-27
Notes: New `.claude/rules/12-runner-cap-add-minimal.md` documents the minimum cap set (CHOWN, DAC_OVERRIDE, FOWNER, KILL, SETGID, SETUID) and explicitly forbids re-adding SYS_ADMIN, SYS_PTRACE, NET_ADMIN, NET_RAW, SYS_MODULE, MKNOD without a per-line annotation AND a SECURITY.md paragraph. Indexed in rules README.

#### [N-46] RULE — Added rule 13: `Dockerfile` must not `COPY . .` or `ADD .`
Fixed: 2026-05-27
Notes: New `.claude/rules/13-dockerfile-no-broad-copy.md` forbids whole-context copies that would bring `.env`, `*.pem`, `.git/`, `secrets/` into the image layer (`.dockerignore` is defense-in-depth but `COPY .` + a one-line `.dockerignore` mistake = silent secret leak). Indexed in rules README.

#### [TODO-OIDC] — TODO.md "OIDC token integration documentation" closed
Fixed: 2026-05-27
Notes: Added a comprehensive OIDC section to `docs/OPERATIONS.md` covering AWS / GCP / Azure federation, the required `permissions: id-token: write`, an end-to-end example with `aws-actions/configure-aws-credentials@v4`, and the GHES note about the per-instance OIDC issuer URL. Moved the item from the "In progress / future" section to "Done" in `TODO.md`.

#### [ENV-CLARITY] — `.env.example` confusing default for `GITHUB_REPO_OWNER`
Fixed: 2026-05-27
Notes: `GITHUB_REPO_OWNER=your-org` was misleading for the org-scope default — entrypoint ignores it but the literal placeholder suggested it was used. Cleared the default to empty and added a comment explaining when each scope reads which vars.

### Pass 52 — 2026-05-27 (close-out: cosmetics elevated to blocking)

#### [N-23] `RUNNER_LABELS` env var is set but unused for runner-N services
Fixed: 2026-05-27
Notes: Added a commented `# RUNNER_LABELS=self-hosted,linux,x64,docker,ephemeral,custom` entry to `.env.example` with explanation that it bypasses the `_DEFAULT` + `_EXTRA` pattern for bare `docker run -e` usage. The compose runner-* services still use the standard label-pair flow.

#### [N-19] `GITHUB_HOST` env var is set everywhere but never read by code
Fixed: 2026-05-27
Notes: `entrypoint.sh` now reads `GITHUB_HOST` and derives `GITHUB_API_URL=https://<host>/api/v3` and `GITHUB_WEB_URL=https://<host>` when host ≠ `github.com`. Explicit overrides via `GITHUB_API_URL` / `GITHUB_WEB_URL` still take precedence (compose-style `:=` assignment). `docs/ENVIRONMENT-VARIABLES.md`, `.env.example`, and `SETUP.md` updated. New SETUP.md §10 "GitHub Enterprise Server (GHES)" walks operators through the setup. `CHANGELOG.md` added (previously referenced from `CONTRIBUTING.md` but didn't exist) and linked from README.

### Pass 51 — 2026-05-27 (user-authorised settings.json registration + path-portability fix)

#### [N-32] HIGH — Hook commands use bare relative paths, breaking when `cwd ≠ project root`
Fixed: 2026-05-27
Notes: Per the [Claude Code hooks reference](https://code.claude.com/docs/en/hooks), hook command strings are invoked with whatever `cwd` Claude has at the time — which is not guaranteed to be the project root (worktrees, `cd` inside a session, subagent execution all break the assumption). Bare paths like `.claude/hooks/foo.sh` silently fail in those cases (`No such file or directory`). The fix is the documented placeholder `${CLAUDE_PROJECT_DIR}` which always expands to the project root before the command runs. All 13 hook commands in `.claude/settings.json` were updated from `".claude/hooks/<name>.sh"` to `"${CLAUDE_PROJECT_DIR}/.claude/hooks/<name>.sh"`. Verified: each path resolves to an executable file after expansion.

#### [N-22] `.claude/settings.json` does not register the new hook commands
Fixed: 2026-05-27
Notes: The previous session was blocked by the auto-mode classifier (which treats edits to `.claude/settings.json` as agent self-modification). User invoked `/nitpicker do the .claude/settings.json changes` to authorise the registration explicitly. The seven new hooks (`block-runner-socket-mount`, `block-unpinned-base-image`, `block-shell-strict-mode-removal`, `block-token-logging`, `block-cat-secrets`, `validate-dockerfile-on-edit`, `validate-entrypoint-arithmetic`) are now wired into the PreToolUse / PostToolUse pipelines.

Final hook layout:

- **PreToolUse → Edit|Write (6 hooks)** — `block-env-edit`, `block-secret-patterns`, `block-runner-socket-mount`, `block-unpinned-base-image`, `block-shell-strict-mode-removal`, `block-token-logging`.
- **PreToolUse → Bash (2 hooks)** — `block-force-push-main`, `block-cat-secrets`.
- **PostToolUse → Edit|Write (5 hooks)** — `post-edit-lint`, `validate-compose-on-edit`, `validate-dockerfile-on-edit`, `validate-entrypoint-arithmetic`, `warn-entrypoint-token-handling`.

Verified: JSON parses, every referenced hook resolves to an executable file, every hook exits 0 on a benign no-op invocation (no spurious blocking).

### Pass 2-10 — 2026-05-26 (deeper static + adversarial)

#### [N-24] HIGH — SIGTERM race window before runner_pid is assigned
Fixed: 2026-05-26
Notes: Previously deferred as N-21 because the window is microseconds wide. Re-evaluated under aggressive iteration: even a single missed signal during graceful shutdown means an orphaned listener that gets SIGKILL'd 2 minutes later, which is exactly the failure mode `stop_grace_period` was added to prevent. Added a `pending_signal` global that `_forward_to_runner` writes when `runner_pid` is empty; `main()` replays the queued signal immediately after `runner_pid=$!`. N-21 retired.

#### [N-25] MEDIUM — Healthcheck false positive on workflow processes containing 'run.sh'
Fixed: 2026-05-26
Notes: `scripts/healthcheck.sh` used `*run.sh*` substring match across all /proc cmdlines. A workflow that runs a script anywhere on the filesystem named `run.sh` (e.g. `./vendor/some-tool/run.sh`) would falsely satisfy the healthcheck even if the runner listener had died. Tightened the match to anchor on `/home/runner/run.sh` (the runner's own path) or `/home/runner/bin/Runner.Listener` (the upstream binary). Runtime is unchanged but the false-positive window is closed.

#### [N-26] MEDIUM — `extract_token` accepts empty string `""` returned by API
Fixed: 2026-05-26
Notes: `jq -r '.token // empty'` only catches `null` / absent, not an empty string. If GitHub's API ever returned `{"token":""}` (extremely unlikely but possible during partial outages), we'd hand `--token ""` to `config.sh` and get an opaque error from the runner. Added a length sanity check in `extract_token`: any token shorter than 10 characters is rejected with a clear error message. GitHub App installation/registration tokens are always ≥40 chars.

#### [N-27] LOW — `curl --max-time 30` may be too aggressive for slow networks
Fixed: 2026-05-26
Notes: `--max-time` in curl is per-attempt (not total — verified). 30s × 3 retries = 90s worst case for a token fetch. Bumped to 60s × 3 retries = 180s. Also documented the retry+timeout policy in a comment block and added a `User-Agent: ivuorinen/github-actions-runner-setup` header so GitHub-side rate-limit dashboards can identify our traffic.

### Pass 11-20 — 2026-05-26 (adversarial hook bypass)

#### [N-28] HIGH — `block-cat-secrets` bypass via `bash -c "cat .env"`
Fixed: 2026-05-26
Notes: The original hook split the command on shell separators (`;|&\n`) and inspected each part. A wrapper `bash -c "cat .env"` is a single shell word from the splitter's perspective — `bash`, `-c`, `"cat .env"` — and the inspect-segment logic only matched a dump-tool at word-start, so `bash -c` segments passed. Rewrote the hook to (a) normalise quote characters out of the command before inspection so the literal `cat .env` is detected even when quoted, and (b) treat the full command as a single payload to be inspected. Verified against 11 adversarial inputs in this pass.

#### [N-29] HIGH — `block-cat-secrets` bypass via single/double quotes around `.env`
Fixed: 2026-05-26
Notes: `cat '.env'` and `cat ".env"` slipped through because the regex `(^|[[:space:]/])\.env([[:space:]]|$)` requires a whitespace or `/` before `.env` — a quote character is neither. Fixed in the same pass as N-28 by stripping ASCII quote characters from the command before regex matching.

#### [N-30] MEDIUM — `block-runner-socket-mount` bypass via compose long-form volume syntax
Fixed: 2026-05-26
Notes: The hook only matched the short-form `- /var/run/docker.sock:/var/run/docker.sock` pattern. Compose's long-form (`type: bind`, `source:`, `target:`) was not detected. Added a second regex matching `^[[:space:]]*source:[[:space:]]*[\"']?/var/run/docker\.sock` to cover the long form.

#### [N-31] LOW — `validate-entrypoint-arithmetic.sh` false-positive on its own comment
Fixed: 2026-05-26
Notes: The hook's own help text contained the literal example `(( ... & 077 == 0 ))`, which the same hook's grep regex matched when scanning all `.claude/hooks/*.sh`. Rewrote the comment to describe the pattern abstractly and reference rule 09 for the example, eliminating the self-flagging.

### Pass 1 — 2026-05-26

#### [N-1] CRITICAL — PEM mode check always fails due to bash arithmetic operator precedence
Fixed: 2026-05-26
Notes: `scripts/entrypoint.sh` line 259 used `(((8#${key_mode}) & 077 == 0))`. In bash arithmetic, `==` has **higher** precedence than `&`, so the expression parsed as `key & (077 == 0)` = `key & 0` = `0`, which made `((0))` always exit 1, which triggered `|| fail` regardless of the actual file mode — including the required mode 600. **The runner could not start with any PEM mode.** Verified by sandbox test: mode 600 returned FAIL with the original expression, PASS with the fix. Fix: parenthesise the bitwise expression — `((((8#${key_mode}) & 077) == 0))`. Documented as `.claude/rules/09-arithmetic-precedence-bash.md` and added a static-grep hook + CI check to catch regressions.

#### [N-2] socket-proxy had no healthcheck; runners could race against unready proxy
Fixed: 2026-05-26
Notes: Added `healthcheck:` block to `socket-proxy` using `nc -z 127.0.0.1 2375`. Added `depends_on: socket-proxy: condition: service_healthy` to the runner anchor so runners wait for the proxy to be ready before starting.

#### [N-3] socket-proxy filesystem was writable; haproxy doesn't need it
Fixed: 2026-05-26
Notes: Added `read_only: true` plus `tmpfs: /run, /tmp` to socket-proxy. Reduces blast radius if the proxy is ever compromised.

#### [N-4] No resource limits on socket-proxy
Fixed: 2026-05-26
Notes: Added `mem_limit` and `pids_limit` to socket-proxy. Prevents a misbehaving workflow spamming the proxy from DoS-ing other runners.

#### [N-5] No `stop_grace_period` — `docker stop` would SIGKILL mid-job
Fixed: 2026-05-26
Notes: Added `stop_signal: SIGTERM` and `stop_grace_period: 2m` to the runner anchor. Combined with `_forward_to_runner` in `entrypoint.sh`, this allows in-flight jobs to drain before container shutdown.

#### [N-6] No log rotation; `docker logs` grew unbounded
Fixed: 2026-05-26
Notes: Added `logging:` blocks to runner and socket-proxy services with `max-size: 10m` and `max-file: 5/3` for json-file driver. Prevents disk fill on long-running deployments.

#### [N-7] No ulimit nofile; high-fd workloads (browser tests, parallel servers) would hit kernel default
Fixed: 2026-05-26
Notes: Added `ulimits: nofile: {soft: 4096, hard: 8192}` to runner anchor. Tunable via `RUNNER_NOFILE_SOFT` / `RUNNER_NOFILE_HARD`.

#### [N-8] Dockerfile HEALTHCHECK `start-period=30s` too short for slow networks during token fetch
Fixed: 2026-05-26
Notes: Bumped to `start-period=60s` and `retries=5`. Cold start can take >30s when api.github.com is slow.

#### [N-9] Dockerfile lacked OCI annotations for image registries / scanners
Fixed: 2026-05-26
Notes: Added `LABEL org.opencontainers.image.*` for title, description, source, documentation, licenses, vendor, base.name. Renovate / GHCR / Trivy use these to surface image metadata.

#### [N-10] `/usr/local/bin/entrypoint.sh` mode/ownership not explicit
Fixed: 2026-05-26
Notes: Dockerfile now explicitly `chmod 0755` and `chown root:root` the scripts. Previously inherited from COPY's default mode.

#### [N-11] No `.claude/rules/` directory — invariants discovered during reviews lived only in CLAUDE.md comments
Fixed: 2026-05-26
Notes: Created `.claude/rules/` with 10 rules covering: PEM ownership, shell strict mode, no-secret-logging, no socket in runner, YAML anchor merge, digest-pinned images, cleanup-trap isolation, config-var leak prevention, bash arithmetic precedence, no-cd-in-entrypoint. Each rule has a "How to verify" section.

#### [N-12] No hook to enforce digest-pinned `FROM` lines
Fixed: 2026-05-26
Notes: Added `.claude/hooks/block-unpinned-base-image.sh` (PreToolUse: Edit/Write) that refuses edits to Dockerfile or compose files with un-pinned `image:` / `FROM` references.

#### [N-13] No hook to prevent re-introducing `/var/run/docker.sock` mount into runner services
Fixed: 2026-05-26
Notes: Added `.claude/hooks/block-runner-socket-mount.sh`. Allows the mount only in the `socket-proxy` block.

#### [N-14] No hook to enforce `set -Eeuo pipefail` on new shell scripts
Fixed: 2026-05-26
Notes: Added `.claude/hooks/block-shell-strict-mode-removal.sh`. Catches Write operations creating a `.sh` file without strict mode in the first 20 lines.

#### [N-15] No hook to block logging of token variables in entrypoint
Fixed: 2026-05-26
Notes: Added `.claude/hooks/block-token-logging.sh`. Refuses edits that introduce `log/echo/printf "...$jwt..."` patterns.

#### [N-16] No bash hook to prevent `cat .env` / `cat *.pem` during interactive sessions
Fixed: 2026-05-26
Notes: Added `.claude/hooks/block-cat-secrets.sh` (PreToolUse: Bash). Blocks `cat/less/head/tail/...` of `.env` and `.pem` files, plus `env`/`printenv > file` without filtering.

#### [N-17] No CI smoke test that the entrypoint refuses bad PEM modes
Fixed: 2026-05-26
Notes: `ci-docker.yml` now boots the built image with a deliberately mode-644 throwaway PEM and asserts the entrypoint exits non-zero with the expected error. This is the regression guard for N-1.

#### [N-18] No CI lint guard against the operator-precedence bug class
Fixed: 2026-05-26
Notes: `ci-lint.yml` now runs a `grep` regression check against `scripts/entrypoint.sh` for the `(a OP b == c)` pattern (where OP is `&|^`). Combined with `validate-entrypoint-arithmetic.sh` (post-edit hook).

#### [N-20] No `docs/ARCHITECTURE.md`, `OPERATIONS.md`, `TROUBLESHOOTING.md`, `ENVIRONMENT-VARIABLES.md`, `SECURITY.md`
Fixed: 2026-05-26
Notes: All five added under `docs/`. `README.md` now indexes them. Root `SECURITY.md` (disclosure policy) and `CONTRIBUTING.md` also added. `Makefile` covers day-to-day ops (`make up`, `make lint`, etc.). `TODO.md` rewritten as `Roadmap` with completed items moved to "Done".

## Invalid

### Pass 53 — 2026-05-27

#### [N-43] Dockerfile has two `USER root` directives — second is dead code
Notes: Re-examined the base image `ghcr.io/actions/actions-runner:2.334.0`, which ends with `USER runner`. The first `USER root` on line 24 is required so that the subsequent `RUN apt-get install` executes as root; the second `USER root` on line 72 is the runtime user. Both are load-bearing — removing either breaks the build (first) or runtime PEM access (second). Finding withdrawn.

### Pass 1 — 2026-05-26

#### [N-A] `--max-time 30` on curl could be insufficient with retries
Notes: Tested in sandbox — curl `--max-time` is per-attempt, not total. With `--retry 3 --retry-all-errors`, three full 30s attempts are allowed. For token endpoints this is plenty. Finding withdrawn.
