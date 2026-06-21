# Nitpicker Findings
Generated: 2026-05-26
Last validated: 2026-06-21 (Pass 107: adversarial review of the PR #24 hardening changes themselves — 4 findings, all fixed; security_opt guard false-positive, advisory-hook test coverage, dead store, stale comment)

## Summary
- Total: 81 | Open: 0 | Fixed: 80 | Invalid: 1 (machine-counted canonical `N-<n>` findings. Pass 107 added N-79–N-82 (4 findings, all fixed in-pass). Pass 106 fixed its own 9 findings, corrected the prior 69/1 mis-count, and canonicalized two ad-hoc Pass-53 ids — `TODO-OIDC`→`N-47`, `ENV-CLARITY`→`N-48`. One legacy invalid finding, `N-A` (Pass 1), keeps its label because its era's numeric id `N-21` was explicitly retired; it is intentionally not machine-counted.)
- Iterations 1-10: 23 findings (1 Critical + 8 High + 14 Medium/Low). All fixed.
- Iterations 11-25: 5 findings (1 High + 4 Medium/Low). All fixed.
- Iterations 26-50: 19 regression checks across linters, hooks, and PEM-mode invariants. All green. 0 new findings.
- Pass 53: 11 new findings (1 Critical + 5 High + 5 Medium). All fixed. 1 Invalid.
- Pass 54: 1 new finding (Medium). Fixed.
- Pass 55: 1 new finding (High — second-order bypass introduced by the Pass 53 force-push fix). Fixed.
- Pass 56-67: 6 new findings. All fixed.
- Pass 68-102: 3 new findings (curl retry semantics, tmpfs memory accounting undocumented, doc cross-reference gaps for new rules/healthcheck/macOS). All fixed. 32 additional probes ran with no new findings (operational config, doc depth, structural cross-checks).
- Pass 104 (2026-06-21): full re-review against the live Claude Code hook contract + runtime. 8 new findings: 1 Critical (entire `.claude/hooks/*` enforcement layer is a silent no-op — reads `TOOL_INPUT_*` env vars that Claude Code never sets; real input is stdin JSON), 3 Medium (GHES `GITHUB_HOST` derivation defeated by compose URL defaults; no behavioral hook test; rules 06/11/12/13 lack commit-time/CI enforcement), 2 Low (stale Dockerfile base.name label, stale `.env.example` image version), 2 Advisory (comment/code mismatch in `extract_token`, rule-06 "PR time" wording). Root cause of N-61 going undetected for 103 passes: only the hook *logic* was ever reviewed, never whether the hook *fires*.
- Pass 105 (2026-06-21): live functional validation of the built image + socket-proxy + entrypoint. All subsystems passed (socket-proxy 10/10 allow/deny, JWT RS256 verifies, token chain, PEM Phase A/B rejection, full lifecycle Phase C, capstone PEM unreadable by runner user). 1 new finding: N-69 (`no-new-privileges` load-bearing but unenforced — fixed).
- Pass 106 (2026-06-21): goal-directed validation of (a) end-to-end functionality of the runner + socket-proxy, (b) all documentation, and (c) existence of every pinned Docker image. Real `docker build` (exit 0, 2.54 GB, all binaries present), `docker compose config` render + rules 04/05/11/12/N-69 assertions, hadolint/shellcheck/shfmt clean, all 4 guard scripts + the 26/26 hook behavioral test pass, every runnable rule `## Verification` confirmed, full line-by-line `entrypoint.sh` read (logic sound), registry inspection of all 3 pinned images (`docker buildx imagetools inspect`) + all 8 workflow action SHAs (all exist), ~135 documentation claims cross-checked. No Critical/High defects. 9 new findings: 2 Medium (the `no-new-privileges` guard is file-wide not per-service; rule 01 transcribes the PEM-mode arithmetic with the rule-09 anti-pattern), 4 Low (socket-proxy tag `0.4.2`→`v0.4.2`; rule 06 verification snippet false-positive; ARCHITECTURE JWT `exp` off by 60s; rule 06 example stale `2.334.0`), 3 Advisory. Pass-104/105 fixed invariants re-confirmed — no regressions. All 9 were then fixed and re-verified this pass (N-70 guard proven against a synthetic per-service `security_opt` override at the offending line; `test-hooks.sh` 26/26; shellcheck/shfmt clean; rule-06 verification now empty; `docker compose config` valid). Audit-file housekeeping (same pass): the 10 historical `### Pass N` headers that used range/parenthetical forms were normalized to the strict `Pass N — date` form (descriptions preserved as italic subtitles), and the two ad-hoc Pass-53 ids `TODO-OIDC`/`ENV-CLARITY` were canonicalized to `N-47`/`N-48`; `check-audit-consistency.py` now reports the file consistent (0 errors).
- Pass 107 (2026-06-21): adversarial review of the PR #24 hardening changes themselves — the two new pre-commit scripts, the 17 stdin-JSON hook edits, and the compose/entrypoint changes. 4 new findings: 1 Medium (N-79: the `security_opt` per-service `awk` in `check-security-invariants.sh` false-positives when a comment or blank line precedes `no-new-privileges:true` — proven against a crafted compose), 1 Low (N-80: `test-hooks.sh` covered only the 11 PreToolUse blockers, leaving the 6 advisory PostToolUse hooks — equally hit by the N-61 stdin bug — unguarded), 2 Advisory (N-81 dead `arith_open` store; N-82 stale `TOOL_INPUT_new_string` comment). Verified-correct in the same review and intentionally NOT filed: the entrypoint `RUNNER_REMOVE_TOKEN` fallback (a global, not `local`, so the `||` branch fires on failure), the `: "${VAR:=default}"` GHES URL derivation against the now-empty compose defaults, and the `cap_add` guard's handling of indented comments/blank lines. All 4 fixed and re-verified in-pass (security_opt regression matrix c1-c4 + genuine-miss e1-e2; `test-hooks.sh` 26→32 cases all green; shellcheck/shfmt clean; the repo's own compose still passes).

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

_None._ Pass 107 (2026-06-21) found 4 issues (1 Medium, 1 Low, 2 Advisory; 0 Critical/High);
all were fixed and re-verified this pass — see **Fixed → Pass 107** below.

## Fixed

### Pass 107 — 2026-06-21

#### [N-79] `check-security-invariants.sh` `security_opt` per-service check false-positives on a comment or blank line before the flag
Category: reliability
Area: `scripts/pre-commit-hooks/check-security-invariants.sh` (the `security_opt` block-form `awk`)
Problem: The `awk` that implements the N-70 per-service check treats ANY non-list line after `security_opt:` as the end of the block via the catch-all rule `in_so { if (!has) print bl; in_so=0 }`. A `security_opt:` block whose first child is a YAML comment or a blank line is reported as missing `no-new-privileges:true` even when the flag is present on a following line.
Evidence: A compose with `security_opt:` / `      # hardening` / `      - no-new-privileges:true` exits 1 with "a security_opt block omits 'no-new-privileges:true' ... at line(s): 4", although the flag is on the next line. The `cap_add` `awk` (specific end-conditions) and the inline-array form were not affected.
Impact: False pre-commit/CI failures on valid, idiomatic YAML (comments and blank lines are common inside lists). Blocks legitimate commits and pressures contributors toward `--no-verify`, defeating the backstop N-64 added.
Fix: Skip blank and comment lines while scanning the block (`in_so && /^[[:space:]]*#/ { next }` and `in_so && /^[[:space:]]*$/ { next }`) before the catch-all end-of-block rule. Re-verified the genuine-miss cases — including a comment before a truly missing flag in a second service — still fail, and the repo's own compose still passes.

#### [N-80] `test-hooks.sh` did not exercise the 6 advisory PostToolUse hooks
Category: tests
Area: `scripts/pre-commit-hooks/test-hooks.sh`
Problem: The behavioral test asserted block/allow exit codes for the 11 PreToolUse blockers but never invoked `post-edit-lint`, `validate-compose-on-edit`, `validate-dockerfile-on-edit`, `validate-entrypoint-arithmetic`, `validate-shell-strict-mode`, or `warn-entrypoint-token-handling`. All six were equally affected by the N-61 stdin regression (they read `TOOL_INPUT_*` env vars and did nothing). They always exit 0, so the exit-code model does not apply, but they emit a stderr warning on a violation — a regression that broke their stdin parsing would silently return them to no-op with no test signal. The header comment also overclaimed ("feeds ... payloads to each hook").
Evidence: `grep` of the six hook names in `test-hooks.sh` returned no `run_case` invocations.
Impact: The silent-no-op regression class the test exists to prevent stayed unguarded for 6 of 17 hooks.
Fix: Added a `run_warn_case` helper that asserts stderr presence/absence, plus warn/quiet cases for the three dependency-free advisory hooks (`validate-shell-strict-mode`, `validate-entrypoint-arithmetic`, `warn-entrypoint-token-handling`); the other three shell out to external linters (`shfmt`/`hadolint`/`docker compose`) and are left to those tools' own suites. Coverage went 26 → 32 cases. Corrected the header comment.

#### [N-81] Dead store of `arith_open` in `validate-entrypoint-arithmetic.sh`
Category: maintainability
Area: `.claude/hooks/validate-entrypoint-arithmetic.sh:49-50`
Problem: `arith_open` was assigned a value and then immediately overwritten on the next line before any use — a dead store left over from building the self-non-matching regex.
Evidence: The first assignment's value was never read; only the second assignment feeds `trap_re`.
Impact: None functional; a confusing leftover in a security-relevant hook.
Fix: Removed the dead first assignment.

#### [N-82] Stale `TOOL_INPUT_new_string` reference in a hook comment
Category: maintainability
Area: `.claude/hooks/block-shell-strict-mode-removal.sh:7`
Problem: A comment still referred to `TOOL_INPUT_new_string`, terminology from the pre-N-61 env-var era; the hook now reads `.tool_input.new_string` from stdin JSON. The substantive point (the new_string field is a partial diff) remains correct.
Evidence: `grep TOOL_INPUT_ .claude/hooks/` matched only this comment.
Impact: Minor confusion; no functional effect.
Fix: Reworded to "the new_string payload field".

### Pass 106 — 2026-06-21

Goal-directed validation of (a) end-to-end functionality of the runner +
socket-proxy, (b) all documentation, and (c) existence of every pinned Docker
image (method/result in the Pass 106 Summary bullet). No Critical/High defects.
All nine findings below were fixed in this pass and the fixes re-verified
together: shellcheck + shfmt clean on the two edited scripts; the N-70 guard
proven to reject a synthetic per-service `security_opt` override (exit 1 at the
offending line) while the real files still pass; `test-hooks.sh` 26/26; the
rule-06 verification command now returns empty; `docker compose config` valid.
Each finding's "Fix:" line records the change that was applied.

#### [N-70] `check-security-invariants.sh` verifies `no-new-privileges` file-wide, not per runner service
Category: reliability
Area: `scripts/pre-commit-hooks/check-security-invariants.sh:56-61`, `docker-compose.yml:38-39`
Problem: The N-69 guard asserts `no-new-privileges:true` with a single file-wide `grep` that needs only ONE match anywhere in the compose file. `security_opt` lives in the `&runner-common` anchor, but YAML merge (`<<:`) REPLACES — does not deep-merge — a mapping key, exactly like `environment:` (rule 05). A runner service that declares its own `security_opt:` drops `no-new-privileges` while the anchor's occurrence (and socket-proxy's) keep the grep green.
Evidence: Adding to any runner —
```yaml
  runner-2:
    <<: *runner-common
    security_opt:
      - seccomp:unconfined
```
makes `docker compose config` render runner-2 WITHOUT `no-new-privileges:true` (the anchor list is replaced), yet `check-security-invariants.sh docker-compose.yml` still exits 0 because the string remains in the anchor block and on socket-proxy. The guard added specifically to protect a "load-bearing" control cannot detect its most realistic regression.
Impact: A per-service `security_opt` override silently re-opens the `sudo cat /run/secrets/github_app_key` PEM-theft path (the exact scenario N-69 documents) with no CI/commit-time signal.
Fix: Assert per service, not per file — render `docker compose config` and confirm every `runner-*` service's `security_opt` contains `no-new-privileges:true`; or, without docker, fail if any block under `services:` defines a `security_opt:` that omits the flag. Keep the existing `:false` check.

#### [N-71] Rule 01 transcribes the PEM-mode check with the wrong parenthesization — the rule-09 anti-pattern, inside a security rule
Category: docs
Area: `.claude/rules/01-pem-must-be-root-mode-600.md:39`
Problem: Rule 01 documents the entrypoint's mode check as `((((8#${mode}) & 077)) == 0)`, which places `== 0` OUTSIDE the inner arithmetic — precisely the operator-precedence mistake rule 09 exists to prevent. The real code is `((((8#${key_mode}) & 077) == 0))` (comparison INSIDE the `(( ))`). The rule also uses the stale variable name `mode` (the source uses `key_mode`).
Evidence: rule 01:39 `((((8#${mode}) & 077)) == 0)` vs `scripts/entrypoint.sh:338` `((((8#${key_mode}) & 077) == 0))`. A maintainer copying the rule's form to "verify" the check gets a structurally different (broken) expression — self-contradictory given rule 09 and that this line enforces H-1 PEM isolation.
Impact: Misleading documentation of a security-critical invariant; risks a "fix" that aligns correct code to the broken doc.
Fix: Replace the quoted expression with `((((8#${key_mode}) & 077) == 0))` and rename `mode`→`key_mode` to match the source.

#### [N-72] socket-proxy image tag `0.4.2` does not exist on Docker Hub (published tag is `v0.4.2`)
Category: maintainability
Area: `docker-compose.yml:144`, `.claude/rules/06-base-image-must-be-digest-pinned.md:8`
Problem: The pinned reference `tecnativa/docker-socket-proxy:0.4.2@sha256:1f3a6f30…` carries a tag (`0.4.2`, no `v`) that does not exist in the registry; upstream publishes `v`-prefixed tags. The digest is correct and authoritative, so deploy-by-digest is unaffected — which is why it went unnoticed.
Evidence: `docker buildx imagetools inspect tecnativa/docker-socket-proxy:0.4.2` → `ERROR: not found`; Docker Hub API `/tags/0.4.2` → 404; registry v2 manifest GET for `0.4.2` → HTTP 404. `…:v0.4.2` resolves to exactly the pinned digest `sha256:1f3a6f30…b47476` (last_updated 2025-12-16). The base runner (`2.335.1`) and hadolint (`v2.14.0`) pins have correct, consistent tag↔digest pairs.
Impact: (a) a human cannot reproduce via `docker pull tecnativa/docker-socket-proxy:0.4.2`; (b) Renovate tracks this image and a `0.4.2`-vs-`v0.4.2` mismatch can cause mis-detection / stalled updates.
Fix: `image: tecnativa/docker-socket-proxy:v0.4.2@sha256:1f3a6f303320723d199d2316a3e82b2e2685d86c275d5e3deeaf182573b47476` (digest unchanged). Update rule 06's example tag to match.

#### [N-73] Rule 06 "## Verification" command false-positives on the local runner image, contradicting "must produce no output"
Category: docs
Area: `.claude/rules/06-base-image-must-be-digest-pinned.md` (Verification block)
Problem: The rule's documented check `grep -nE 'image:' docker-compose.yml | grep -v '@sha256:'` is stated to "produce no output", but it matches `docker-compose.yml:8` `image: ${RUNNER_IMAGE_NAME:-local/github-app-actions-runner:latest}` — the locally-built runner image, which by design cannot carry a registry digest. So the rule's own verification "fails" on a compliant repo.
Evidence: Running the rule's grep returns line 8. The canonical guard `check-security-invariants.sh:43-44` correctly excludes these with `grep -vE 'local/|[$]\{'` and passes (confirmed by execution this pass).
Impact: An operator following the rule doc to self-check sees a spurious failure and may "fix" a non-issue or distrust the invariant.
Fix: Align the rule's compose verification snippet with the guard: `grep -E '^[[:space:]]*image:' docker-compose.yml | grep -vE 'local/|[$]\{' | grep -v '@sha256:'` (expected: empty).

#### [N-74] ARCHITECTURE.md states JWT `exp=now+540`; actual is `now+480` (`exp=iat+540`, `iat=now-60`)
Category: docs
Area: `docs/ARCHITECTURE.md:56`
Problem: The JWT-minting description gives `exp=now+540`, but the code computes `exp` from `iat` (which is `now-60`), so `exp = now+480`. The total iat→exp validity of 540 s (9 min) is stated correctly elsewhere (line 79); only this term is wrong.
Evidence: doc `iat=now-60, exp=now+540` (ARCHITECTURE.md:56) vs `scripts/entrypoint.sh:30-31` `iat="$((now - 60))"; exp="$((iat + 540))"` → `now+480`.
Impact: Minor numeric inaccuracy in the architecture reference.
Fix: Change `exp=now+540` to `exp=iat+540` (equivalently `exp=now+480`).

#### [N-75] Rule 06 example uses stale runner version 2.334.0 (current pin is 2.335.1)
Category: docs
Area: `.claude/rules/06-base-image-must-be-digest-pinned.md:7,20`
Problem: The worked example shows `FROM ghcr.io/actions/actions-runner:2.334.0@sha256:b6614fce…` and references `2.334.0` in prose, while the live pin is `2.335.1@sha256:08c30b0a…`. Same staleness class as the already-fixed N-65 (Dockerfile label), but in the rule's illustrative example.
Evidence: rule 06:7 `2.334.0@sha256:b6614fce…` vs `Dockerfile:11` `2.335.1@sha256:08c30b0a…`.
Impact: A reader may believe 2.334.0 is current; the example digest no longer matches anything in the repo.
Fix: Update the example to the current 2.335.1 digest, OR de-version it to `<tag>@sha256:<digest>` so it cannot go stale.

#### [N-76] Startup hard-fails if the remove-token pre-fetch errors, despite the cleanup PEM-refetch fallback making it non-essential
Category: reliability
Area: `scripts/entrypoint.sh:355`
Problem: `RUNNER_REMOVE_TOKEN="$(get_remove_token "${installation_token}")"` runs under `set -e`; on an API error `get_remove_token`→`api`→`fail` exits, aborting `main()` before the runner ever registers or runs. Yet `deregister_runner` (lines 198-208) explicitly handles an empty `RUNNER_REMOVE_TOKEN` by re-minting from the still-mounted PEM, so the pre-fetch is declared a non-essential optimization.
Evidence: A transient 5xx on `…/actions/runners/remove-token` (after retries) makes the container exit 1 even though registration (the prior, same-family call) succeeded and cleanup could recover the token later.
Impact: Low — couples startup availability to a step the design treats as optional. Failing fast also has merit (surfaces misconfig); behavior is safe, just stricter than the fallback implies.
Fix (optional): make the pre-fetch non-fatal — `RUNNER_REMOVE_TOKEN="$(get_remove_token "${installation_token}")" || { log 'Warning: remove-token pre-fetch failed; will re-mint from PEM at cleanup'; RUNNER_REMOVE_TOKEN=""; }`.

#### [N-77] OPERATIONS.md log-line table abbreviates the SIGTERM message
Category: docs
Area: `docs/OPERATIONS.md:34`
Problem: The grep-able log-line table shows `Received SIGTERM, forwarding to runner listener`, but the emitted line is `Received SIG${sig}, forwarding to runner listener (PID ${runner_pid}) for graceful shutdown`. The prefix matches for sig=TERM; the `(PID …) for graceful shutdown` suffix is dropped. The other table rows match exactly.
Evidence: OPERATIONS.md:34 vs `scripts/entrypoint.sh:244`.
Impact: Cosmetic — an operator grepping the full quoted string past "…runner listener" finds nothing.
Fix (optional): append `(PID <pid>) for graceful shutdown` (or `…`) to the table cell for parity with the other rows' placeholder style.

#### [N-78] SECURITY-REVIEW-2026-04-20.md carries point-in-time line refs/counts that no longer resolve
Category: docs
Area: `docs/SECURITY-REVIEW-2026-04-20.md` (e.g. :75, :464, :472)
Problem: This dated review references line numbers and counts from the 2026-04-20 codebase (e.g. "docker-compose.yml:95 …digest" is now line 144; "6/6 hooks" is now 17 hooks; a `FROM …2.333.1` example). It is a historical artifact, not live documentation.
Evidence: Cross-checking its cited line numbers against the current tree shows drift (confirmed for the socket-proxy image line, hook count, and FROM example).
Impact: None for setup/operations; flagged only because the validation brief covered line-ref accuracy across all docs.
Fix (optional, no content change required): add a one-line banner at the top — "Line numbers and counts reflect the repository as of 2026-04-20" — so readers don't treat its refs as current.

### Pass 105 — 2026-06-21

Live functional validation of the built image, socket-proxy, and entrypoint
(image builds; socket-proxy 10/10 allow/deny; JWT RS256 verifies; token chain +
error handling; healthcheck logic; rendered-config hardening; runtime CapEff;
PEM rejection Phase A/B; full lifecycle Phase C to config.sh; runtime no-token
logging; capstone PEM unreadable by the runner user). All subsystems passed; one
new hardening finding surfaced.

#### [N-69] `no-new-privileges:true` is load-bearing for PEM isolation but was unenforced
Category: security
Area: `docker-compose.yml`, `scripts/pre-commit-hooks/check-security-invariants.sh`
Problem: The actions-runner base image ships a **setuid-root** `/usr/bin/sudo` and adds the runner user to the `sudo` group. `no-new-privileges:true` neutralizes this, but nothing enforced the flag's presence — an operator or regression removing it (or setting it `false`) would let a workflow `sudo cat /run/secrets/github_app_key` and steal the GitHub App key, collapsing the entire credential-isolation model.
Evidence: Live test in the built image — `sudo` is `-rwsr-xr-x`; WITH `no-new-privileges` every escalation attempt failed (`sudo -n cat` denied, `sudo id` blocked, runner-user `CapEff=0000000000000000`). Compose sets the flag on all runners, but `check-security-invariants.sh` did not assert it, and no rule guarded it.
Impact: A single accidental edit removing the flag silently opens a full PEM-theft path from any workflow job.
Fix: Extended `check-security-invariants.sh` to fail if a compose file lacks `no-new-privileges:true` or sets it `false` (runs in CI + pre-commit); added a load-bearing comment in `docker-compose.yml`. Verified: real files pass; synthetic missing/false both fail; lint clean.
Fixed: 2026-06-21
Notes: Surfaced by the runtime escalation test, not static review — the dependency is only visible when you actually try to escalate in the real image.

### Pass 104 — 2026-06-21

Adversarial re-review against the live Claude Code hook contract and runtime.
Eight new findings. The deployed-runtime security (PEM isolation, socket-proxy,
caps, no-new-privileges, token handling) verified sound; failures were in the
meta-enforcement layer and a GHES config path. Each finding's Fix line was
applied and verified — see the per-finding evidence below.

#### [N-61] Entire `.claude/hooks/*` enforcement layer was a silent no-op (reads env vars; Claude Code sends stdin JSON)
Category: security
Area: `.claude/hooks/*.sh` (all 17 hooks), `.claude/settings.json`
Problem: Every hook reads tool input from `${TOOL_INPUT_command:-}` / `${TOOL_INPUT_FILE_PATH:-}` / `${TOOL_INPUT_new_string:-}` / `${TOOL_INPUT_content:-}` environment variables. Claude Code does not set any `TOOL_INPUT_*` variables — per the official hooks reference, a command hook receives the tool input as a JSON object on **stdin** (`{"tool_name":...,"tool_input":{"command":...}}`). Each hook's first action is `[[ -z "${command}" ]] && exit 0` (or the file_path equivalent), so with the env var unset every hook reads `""` and immediately exits 0 (allow). None read stdin; none use jq.
Evidence:
1. Official docs (code.claude.com/docs/en/hooks): "For command hooks, input arrives on stdin"; the documented PreToolUse schema is stdin JSON with no env-var form. Hooks only inherit the parent env plus `CLAUDE_PROJECT_DIR`.
2. Live session test: running `cat .env` via the Bash tool was **not** blocked even though `block-cat-secrets.sh` is registered on the Bash matcher — `cat` executed and failed only on the missing file.
3. Direct test: `printf '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}' | bash .claude/hooks/block-cat-secrets.sh` → exit 0 (allow). `TOOL_INPUT_command='cat .env' bash .claude/hooks/block-cat-secrets.sh </dev/null` → exit 2 (block). The hook fires only on an env var Claude never sets.
4. `grep` over all hooks: 17/17 read `TOOL_INPUT_*`; 0/17 read stdin or jq.
Impact: All 17 client-side guards are disabled — secret-dump blocking, force-push-to-main, socket-mount (rule 04), digest-pin (rule 06), strict-mode (rule 02), token-logging (rule 03), socket-proxy widening (rule 11), cap widening (rule 12), broad-COPY (rule 13), `.env` edit, secret-pattern scan, and all 6 PostToolUse validators. Rules 03/06/11/12/13 and the secret/force-push guards have no other automated enforcement, so those invariants are unguarded against regressions made in a Claude session. `SECURITY.md` and four rule files assert these hooks enforce trust boundaries; those claims are false until this is fixed.
Fix: Rewrite each hook to read the JSON payload from stdin and extract fields with jq: `input="$(cat)"; command="$(jq -r '.tool_input.command // empty' <<<"$input")"`; `file_path="$(jq -r '.tool_input.file_path // empty' <<<"$input")"`; `content="$(jq -r '.tool_input.new_string // .tool_input.content // empty' <<<"$input")"`. Add a jq-presence guard that fails closed (exit 2) in the blocking PreToolUse hooks. Add a behavioral test (N-63) wired into CI so this cannot regress silently.

#### [N-62] GHES `GITHUB_HOST`-only setup (documented method (a)) was defeated by compose URL defaults
Category: correctness
Area: `docker-compose.yml` (GITHUB_API_URL/GITHUB_WEB_URL ×3), `.env.example`, `scripts/entrypoint.sh:273-283`
Problem: entrypoint derives the GHES API/web URLs from `GITHUB_HOST` only when `GITHUB_API_URL`/`GITHUB_WEB_URL` are unset/empty (`: "${GITHUB_API_URL:=https://${GITHUB_HOST}/api/v3}"`). But docker-compose.yml sets `GITHUB_API_URL: ${GITHUB_API_URL:-https://api.github.com}` (and WEB_URL likewise) on every runner service, so the container always receives a non-empty `https://api.github.com`. The `:=` default becomes a no-op and the derivation never runs under compose. `.env.example` also ships both URL lines uncommented at the github.com values.
Evidence: With `.env` containing only `GITHUB_HOST=ghes.example.com`, compose interpolates `GITHUB_API_URL=https://api.github.com`; entrypoint takes the `!= github.com` branch but `:=` leaves the already-set value untouched, so the runner calls `https://api.github.com/app/installations/...` with a GHES app and fails auth. `.env.example:23`, `docs/ENVIRONMENT-VARIABLES.md:63`, and `SETUP.md:255-264` all promise "set GITHUB_HOST only — entrypoint derives the API and web URLs automatically."
Impact: The documented GHES quick-path is broken via the only supported deployment mechanism. A GHES operator following SETUP.md gets a confusing auth failure against api.github.com. Method (b) (set all three) works; method (a) does not.
Fix: In docker-compose.yml change the three pairs to `GITHUB_API_URL: ${GITHUB_API_URL:-}` / `GITHUB_WEB_URL: ${GITHUB_WEB_URL:-}` so entrypoint owns defaulting/derivation; comment out the `GITHUB_API_URL=`/`GITHUB_WEB_URL=` lines in `.env.example` so method (a) is the default. `${var:=}` treats empty as unset, so derivation fires.

#### [N-63] No behavioral test that hooks actually block; only an executable-bit check
Category: tests
Area: `.github/workflows/ci-lint.yml`, `.claude/hooks/`
Problem: CI's only hook check is `find .claude/hooks -name '*.sh' -not -perm -u+x` (executable bit). Nothing feeds a representative payload to a hook and asserts block/allow. This is why N-61 — a 100%-dead enforcement layer — went undetected through 103 passes of detailed per-hook logic review.
Evidence: `ci-lint.yml:62-73` checks executability only; no test pipes stdin JSON and asserts an exit code.
Impact: Any future regression to the hook input contract or logic passes CI silently.
Fix: Add `scripts/pre-commit-hooks/test-hooks.sh` that pipes canonical PreToolUse JSON (block and allow cases) into each hook and asserts exit 2 / exit 0; run it from ci-lint.yml and as a pre-commit local hook.

#### [N-64] Rules 03/06/11/12/13 + secret/force-push guards have no commit-time/CI enforcement, only the client-side hooks
Category: reliability
Area: `.github/workflows/ci-lint.yml`, `scripts/pre-commit-hooks/`, `.claude/rules/{06,11,12,13}`
Problem: Even after N-61 is fixed, the `.claude/hooks` mediate only edits made through Claude Code. A human (or any non-Claude tool) editing docker-compose.yml/Dockerfile directly faces no guard for digest-pinning (06), socket-proxy surface (11), runner caps (12), or broad COPY (13). Rules 04 and 09 already have CI/pre-commit scripts; 06/11/12/13 do not.
Evidence: Each rule's "Verification" section is a one-line grep, but none of those greps run in CI or pre-commit. `ci-lint.yml` runs only the rule-04 and rule-09 scripts.
Impact: The repo's security invariants are only as strong as the weakest editor path; a direct PR adding `CONTAINERS: 1` or `SYS_PTRACE` to compose passes all CI.
Fix: Add the documented verification greps as a CI step ("Verify security invariants") and/or pre-commit local hooks mirroring `check-no-docker-sock-in-runner.sh`, covering rules 06/11/12/13.

#### [N-65] Dockerfile `org.opencontainers.image.base.name` label was stale (`2.334.0` vs `FROM` `2.335.1`)
Category: maintainability
Area: `Dockerfile:11,21`
Problem: FROM pins `actions-runner:2.335.1@sha256:...` but the `base.name` annotation still says `2.334.0`. Renovate updates the FROM tag/digest but not the free-text LABEL, so it drifts every bump.
Evidence: `Dockerfile:11` → `2.335.1`; `Dockerfile:21` → `...image.base.name="ghcr.io/actions/actions-runner:2.334.0"`.
Impact: Scanners/registries surface a base image that doesn't match the actual base layer; misleading provenance.
Fix: Update the label to `2.335.1`. To stop recurring drift, drop the version from `base.name` (use `ghcr.io/actions/actions-runner`) or add a Renovate customManager for the LABEL line.

#### [N-66] `.env.example` `id runner` hint references stale runner image `2.333.1`
Category: docs
Area: `.env.example:62`
Problem: The RUNNER_UID verification comment runs `docker run --rm ghcr.io/actions/actions-runner:2.333.1 id runner` — two minor versions behind the pinned base (2.335.1).
Evidence: `.env.example:62`.
Impact: Operator pulls an outdated image to verify a UID; minor confusion.
Fix: Bump to 2.335.1 or make the hint version-agnostic.

#### [N-67] `extract_token` length-guard comment said "≥40 chars" but the check is `< 10`
Category: maintainability
Area: `scripts/entrypoint.sh:128-133`
Problem: The comment states tokens are "≥40 chars" but the guard rejects only length `< 10`. The loose bound is fine defensively; the comment overstates it.
Evidence: `entrypoint.sh:131` → `if [[ "${#token}" -lt 10 ]]`.
Impact: Misleading comment; no runtime effect.
Fix: Reword the comment to match the `< 10` sanity bound.

#### [N-68] Rule 06 says digest-pinning is "Enforced at PR time by `.claude/hooks/...`"; hooks are client-side session-time
Category: docs
Area: `.claude/rules/06-base-image-must-be-digest-pinned.md:43`
Problem: The hook runs at edit time inside a Claude Code session, not at PR/CI time. CI does not currently check digest pinning (see N-64).
Evidence: rule 06 line 43.
Impact: Overstates where enforcement happens; a reader assumes CI blocks unpinned images.
Fix: Reword to "Enforced client-side at edit time by the hook (and, once N-64 lands, by CI)." — done.

### Pass 103 — 2026-05-28

_Pre-commit re-validation of working-tree deltas._

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

### Pass 102 — 2026-05-27

_Passes 68-102 — operational + structural exhaustion._

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

### Pass 67 — 2026-05-27

_Passes 56-67 — rule-enforcing hooks, API-contract harden, doc gaps._

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

### Pass 55 — 2026-05-27

_Self-review of Pass 53/54 deltas._

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

### Pass 54 — 2026-05-27

_Second-order audit._

#### [N-49] MEDIUM — `block-cat-secrets.sh` missed `/run/secrets/` and `github_app_key` paths
Fixed: 2026-05-27
Notes: `is_pem_target()` only matched the `.pem` filename suffix. But the actual PEM inside the container lives at `/run/secrets/github_app_key` (set by `GITHUB_APP_PRIVATE_KEY_FILE` in compose) — no `.pem` extension. A `cat /run/secrets/github_app_key` inside a runner shell would dump the most sensitive credential in the system and the hook would not block. Extended `is_pem_target()` to also match `/run/secrets/<anything>`, any path containing `github_app_key`, and any `private-key` token. Verified: 6/7 PEM-shaped paths now BLOCK, plus the existing `.pem` matcher, plus `README.md` still ALLOWs.

### Pass 53 — 2026-05-27

_Adversarial hook-bypass + CI correctness._

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

#### [N-47] — TODO.md "OIDC token integration documentation" closed (formerly tracked as ad-hoc id `TODO-OIDC`)
Fixed: 2026-05-27
Notes: Added a comprehensive OIDC section to `docs/OPERATIONS.md` covering AWS / GCP / Azure federation, the required `permissions: id-token: write`, an end-to-end example with `aws-actions/configure-aws-credentials@v4`, and the GHES note about the per-instance OIDC issuer URL. Moved the item from the "In progress / future" section to "Done" in `TODO.md`.

#### [N-48] — `.env.example` confusing default for `GITHUB_REPO_OWNER` (formerly tracked as ad-hoc id `ENV-CLARITY`)
Fixed: 2026-05-27
Notes: `GITHUB_REPO_OWNER=your-org` was misleading for the org-scope default — entrypoint ignores it but the literal placeholder suggested it was used. Cleared the default to empty and added a comment explaining when each scope reads which vars.

### Pass 52 — 2026-05-27

_Close-out: cosmetics elevated to blocking._

#### [N-23] `RUNNER_LABELS` env var is set but unused for runner-N services
Fixed: 2026-05-27
Notes: Added a commented `# RUNNER_LABELS=self-hosted,linux,x64,docker,ephemeral,custom` entry to `.env.example` with explanation that it bypasses the `_DEFAULT` + `_EXTRA` pattern for bare `docker run -e` usage. The compose runner-* services still use the standard label-pair flow.

#### [N-19] `GITHUB_HOST` env var is set everywhere but never read by code
Fixed: 2026-05-27
Notes: `entrypoint.sh` now reads `GITHUB_HOST` and derives `GITHUB_API_URL=https://<host>/api/v3` and `GITHUB_WEB_URL=https://<host>` when host ≠ `github.com`. Explicit overrides via `GITHUB_API_URL` / `GITHUB_WEB_URL` still take precedence (compose-style `:=` assignment). `docs/ENVIRONMENT-VARIABLES.md`, `.env.example`, and `SETUP.md` updated. New SETUP.md §10 "GitHub Enterprise Server (GHES)" walks operators through the setup. `CHANGELOG.md` added (previously referenced from `CONTRIBUTING.md` but didn't exist) and linked from README.

### Pass 51 — 2026-05-27

_User-authorised settings.json registration + path-portability fix._

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

### Pass 10 — 2026-05-26

_Passes 2-10 — deeper static + adversarial._

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

### Pass 20 — 2026-05-26

_Passes 11-20 — adversarial hook bypass._

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
