#!/usr/bin/env bash
# Behavioral test for the .claude/hooks/* enforcement hooks.
#
# Each Claude Code PreToolUse/PostToolUse command hook receives the tool
# payload as JSON on stdin (see https://code.claude.com/docs/en/hooks). This
# test feeds canonical payloads to each hook: PreToolUse blockers are asserted
# on exit code (2 = block, 0 = allow); advisory PostToolUse hooks always exit 0
# and are asserted on whether they emit the expected stderr warning. It exists
# because the only prior CI check was an executable-bit test, which let a
# 100%-dead hook layer (every hook read non-existent TOOL_INPUT_* env vars)
# pass 103 review passes.
#
# Run: scripts/pre-commit-hooks/test-hooks.sh
# Exits non-zero if any hook does not behave as expected.

set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hooks_dir="${repo_root}/.claude/hooks"

if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL: jq is required to run the hook tests (and to run the hooks)." >&2
  exit 1
fi

pass=0
fail=0

# run_case <hook> <expected_exit> <description> <json-payload>
# The payload is passed as an argument (not piped) so the counter increments
# land in this shell rather than a pipeline subshell.
run_case() {
  local hook="$1" expected="$2" desc="$3" payload="$4"
  local rc=0
  printf '%s' "${payload}" | bash "${hooks_dir}/${hook}" >/dev/null 2>&1 || rc=$?
  if [[ "${rc}" -eq "${expected}" ]]; then
    pass=$((pass + 1))
    printf 'PASS  %-34s %s (exit %s)\n' "${hook}" "${desc}" "${rc}"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-34s %s (got exit %s, want %s)\n' "${hook}" "${desc}" "${rc}" "${expected}"
  fi
}

# run_warn_case <hook> <warn|quiet> <description> <json-payload>
# For advisory PostToolUse hooks that always exit 0 but print a stderr warning
# on a violation. Asserts presence (warn) or absence (quiet) of stderr output,
# so a silent stdin-parse regression (the N-61 class) is caught for them too.
run_warn_case() {
  local hook="$1" expect="$2" desc="$3" payload="$4"
  local err got
  err="$(printf '%s' "${payload}" | bash "${hooks_dir}/${hook}" 2>&1 >/dev/null || true)"
  got="quiet"
  [[ -n "${err}" ]] && got="warn"
  if [[ "${got}" == "${expect}" ]]; then
    pass=$((pass + 1))
    printf 'PASS  %-34s %s (%s)\n' "${hook}" "${desc}" "${got}"
  else
    fail=$((fail + 1))
    printf 'FAIL  %-34s %s (got %s, want %s)\n' "${hook}" "${desc}" "${got}" "${expect}"
  fi
}

bash_json() { jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
write_json() { jq -n --arg f "$1" --arg c "$2" '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}'; }

# Assemble the private-key marker from a variable so this test file does not
# itself trip block-secret-patterns when it is written or edited.
pk_word='BEGIN'
pk_marker="-----${pk_word} PRIVATE KEY-----"

# --- block-cat-secrets ------------------------------------------------------
run_case block-cat-secrets.sh 2 'cat .env blocked' "$(bash_json 'cat .env')"
run_case block-cat-secrets.sh 2 'cat PEM mount blocked' "$(bash_json 'cat /run/secrets/github_app_key')"
run_case block-cat-secrets.sh 0 'cat README.md allowed' "$(bash_json 'cat README.md')"
run_case block-cat-secrets.sh 0 'cat .env.example allowed' "$(bash_json 'cat .env.example')"

# --- block-force-push-main --------------------------------------------------
run_case block-force-push-main.sh 2 '--force main blocked' "$(bash_json 'git push --force origin main')"
run_case block-force-push-main.sh 2 '+main refspec blocked' "$(bash_json 'git push origin +main')"
run_case block-force-push-main.sh 0 'normal push allowed' "$(bash_json 'git push origin feature')"
run_case block-force-push-main.sh 0 'force-with-lease allowed' "$(bash_json 'git push --force-with-lease origin feature')"

# --- block-env-edit ---------------------------------------------------------
run_case block-env-edit.sh 2 '.env edit blocked' "$(write_json '/x/.env' 'A=1')"
run_case block-env-edit.sh 0 '.env.example allowed' "$(write_json '/x/.env.example' 'A=1')"

# --- block-secret-patterns --------------------------------------------------
run_case block-secret-patterns.sh 2 'private key blocked' "$(write_json '/x/notes.md' "${pk_marker}")"
run_case block-secret-patterns.sh 0 'benign text allowed' "$(write_json '/x/notes.md' 'just some text')"

# --- block-runner-socket-mount ----------------------------------------------
run_case block-runner-socket-mount.sh 2 'socket mount on runner blocked' \
  "$(write_json '/x/docker-compose.yml' $'services:\n  runner-1:\n    volumes:\n      - /var/run/docker.sock:/var/run/docker.sock\n  socket-proxy:\n    image: x')"
run_case block-runner-socket-mount.sh 0 'socket mount on proxy allowed' \
  "$(write_json '/x/docker-compose.yml' $'services:\n  socket-proxy:\n    volumes:\n      - /var/run/docker.sock:/var/run/docker.sock:ro')"

# --- block-unpinned-base-image ----------------------------------------------
run_case block-unpinned-base-image.sh 2 'unpinned FROM blocked' "$(write_json '/x/Dockerfile' 'FROM alpine:3.19')"
run_case block-unpinned-base-image.sh 0 'digest-pinned FROM allowed' \
  "$(write_json '/x/Dockerfile' 'FROM alpine:3.19@sha256:0000000000000000000000000000000000000000000000000000000000000000')"

# --- block-socket-proxy-widening --------------------------------------------
run_case block-socket-proxy-widening.sh 2 'CONTAINERS:1 blocked' \
  "$(write_json '/x/docker-compose.yml' $'    environment:\n      CONTAINERS: 1')"
run_case block-socket-proxy-widening.sh 0 'allowed surface allowed' \
  "$(write_json '/x/docker-compose.yml' $'    environment:\n      IMAGES: 1\n      PING: 1')"

# --- block-runner-cap-widening ----------------------------------------------
run_case block-runner-cap-widening.sh 2 'SYS_PTRACE blocked' \
  "$(write_json '/x/docker-compose.yml' $'    cap_add:\n      - SYS_PTRACE')"
run_case block-runner-cap-widening.sh 0 'allowed caps allowed' \
  "$(write_json '/x/docker-compose.yml' $'    cap_add:\n      - CHOWN\n      - SETUID')"

# --- block-dockerfile-broad-copy --------------------------------------------
run_case block-dockerfile-broad-copy.sh 2 'COPY . blocked' "$(write_json '/x/Dockerfile' 'COPY . /app')"
run_case block-dockerfile-broad-copy.sh 0 'per-file COPY allowed' \
  "$(write_json '/x/Dockerfile' 'COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh')"

# --- block-shell-strict-mode-removal ----------------------------------------
run_case block-shell-strict-mode-removal.sh 2 'missing strict-mode blocked' \
  "$(write_json '/x/foo.sh' $'#!/usr/bin/env bash\necho hi')"
run_case block-shell-strict-mode-removal.sh 0 'strict-mode allowed' \
  "$(write_json '/x/foo.sh' $'#!/usr/bin/env bash\nset -Eeuo pipefail\necho hi')"

# --- block-token-logging ----------------------------------------------------
# SC2016: the ${jwt} literal is the dangerous pattern under test; do not expand.
# shellcheck disable=SC2016
run_case block-token-logging.sh 2 'token logging blocked' "$(write_json '/x/entrypoint.sh' 'log "token=${jwt}"')"
run_case block-token-logging.sh 0 'metadata logging allowed' \
  "$(write_json '/x/entrypoint.sh' 'log "Obtained installation token"')"

# --- advisory PostToolUse hooks (always exit 0; assert the stderr warning) ---
# These warn-only hooks were equally affected by the env-var/stdin regression
# (N-61); without a warning assertion a silent parse failure would go unnoticed.
tmp_warn="$(mktemp -d)"
trap 'rm -rf "${tmp_warn}"' EXIT

printf '%s\n' '#!/usr/bin/env bash' 'echo hi' >"${tmp_warn}/no-strict.sh"
printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' 'echo hi' >"${tmp_warn}/strict.sh"
run_warn_case validate-shell-strict-mode.sh warn 'missing strict-mode warns' \
  "$(write_json "${tmp_warn}/no-strict.sh" '')"
run_warn_case validate-shell-strict-mode.sh quiet 'full strict-mode silent' \
  "$(write_json "${tmp_warn}/strict.sh" '')"

# Assemble the unparenthesized-trap line from a variable so this test file does
# not itself trip the arithmetic-precedence-trap guard (same tactic as the
# pk_marker above). The generated arith-bad.sh still contains the real literal.
amp='&'
printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' "((a ${amp} b == c))" >"${tmp_warn}/arith-bad.sh"
printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' "((((a ${amp} b)) == c))" >"${tmp_warn}/arith-ok.sh"
run_warn_case validate-entrypoint-arithmetic.sh warn 'unparenthesized & == warns' \
  "$(write_json "${tmp_warn}/arith-bad.sh" '')"
run_warn_case validate-entrypoint-arithmetic.sh quiet 'parenthesized arithmetic silent' \
  "$(write_json "${tmp_warn}/arith-ok.sh" '')"

# shellcheck disable=SC2016
run_warn_case warn-entrypoint-token-handling.sh warn 'token-handling edit warns' \
  "$(write_json '/x/entrypoint.sh' 'installation_token="$(make_jwt x)"')"
run_warn_case warn-entrypoint-token-handling.sh quiet 'unrelated edit silent' \
  "$(write_json '/x/entrypoint.sh' 'echo hello world')"

echo "----------------------------------------"
echo "hook behavior: ${pass} passed, ${fail} failed"
[[ "${fail}" -eq 0 ]]
