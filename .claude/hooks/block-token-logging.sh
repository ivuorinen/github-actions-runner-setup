#!/usr/bin/env bash
# PreToolUse hook: prevent edits to entrypoint.sh that would log token
# material. See .claude/rules/03-no-secret-logging.md
# Exit code 2 = block the tool call

set -Eeuo pipefail

# Claude Code delivers the tool payload as JSON on stdin (NOT environment
# variables). See https://code.claude.com/docs/en/hooks.
if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED: jq not found; $(basename "$0") cannot enforce; failing closed. Install jq." >&2
  exit 2
fi
hook_input="$(cat)"
file_path="$(jq -r '.tool_input.file_path // empty' <<<"${hook_input}" 2>/dev/null || true)"
[[ -z "${file_path}" ]] && exit 0

basename="$(basename "${file_path}")"
case "${basename}" in
entrypoint.sh) ;;
*) exit 0 ;;
esac

content="$(jq -r '.tool_input.new_string // .tool_input.content // empty' <<<"${hook_input}" 2>/dev/null || true)"
[[ -z "${content}" ]] && exit 0

# Look for log/echo/printf/tee statements that expand a token variable
# directly. Examples that should block:
#   log "token=${jwt}"
#   echo "$installation_token"
#   printf '%s\n' "${registration_token}"
#   log "remove token: ${RUNNER_REMOVE_TOKEN}"
#   tee /tmp/out <<< "${jwt}"
#
# `\b` (GNU regex word-boundary) is not portable to BSD grep on macOS,
# so we use the explicit POSIX equivalent: end-of-line OR any non-
# [A-Za-z0-9_] character (which covers `}`, space, quote, `,`, etc.).
if printf '%s\n' "${content}" |
  grep -nE '(^|;|[[:space:]])(log|echo|printf|tee)[[:space:]]+[^#]*\$\{?(jwt|installation_token|registration_token|remove_token|RUNNER_REMOVE_TOKEN)([^A-Za-z0-9_]|$)'; then
  cat >&2 <<'MSG'
BLOCKED: Detected a log/echo/printf statement expanding a token variable
in entrypoint.sh. Token material must never reach stdout/stderr. Log only
metadata (presence, length, expiry) instead. See
.claude/rules/03-no-secret-logging.md
MSG
  exit 2
fi
