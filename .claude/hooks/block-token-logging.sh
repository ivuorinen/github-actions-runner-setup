#!/usr/bin/env bash
# PreToolUse hook: prevent edits to entrypoint.sh that would log token
# material. See .claude/rules/03-no-secret-logging.md
# Exit code 2 = block the tool call

set -Eeuo pipefail

file_path="${TOOL_INPUT_FILE_PATH:-${TOOL_INPUT_file_path:-}}"
[[ -z "${file_path}" ]] && exit 0

basename="$(basename "${file_path}")"
case "${basename}" in
entrypoint.sh) ;;
*) exit 0 ;;
esac

content="${TOOL_INPUT_new_string:-${TOOL_INPUT_content:-}}"
[[ -z "${content}" ]] && exit 0

# Look for log/echo/printf statements that expand a token variable directly.
# Examples that should block:
#   log "token=${jwt}"
#   echo "$installation_token"
#   printf '%s\n' "${registration_token}"
#   log "remove token: ${RUNNER_REMOVE_TOKEN}"
if printf '%s\n' "${content}" |
  grep -nE '(^|;|[[:space:]])(log|echo|printf)[[:space:]]+[^#]*\$\{?(jwt|installation_token|registration_token|remove_token|RUNNER_REMOVE_TOKEN)\b'; then
  cat >&2 <<'MSG'
BLOCKED: Detected a log/echo/printf statement expanding a token variable
in entrypoint.sh. Token material must never reach stdout/stderr. Log only
metadata (presence, length, expiry) instead. See
.claude/rules/03-no-secret-logging.md
MSG
  exit 2
fi
