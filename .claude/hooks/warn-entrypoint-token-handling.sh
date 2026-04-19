#!/usr/bin/env bash
# PostToolUse hook: Warn when editing security-critical token handling in entrypoint.sh

set -Eeuo pipefail

file_path="${TOOL_INPUT_FILE_PATH:-${TOOL_INPUT_file_path:-}}"
[[ -z "${file_path}" ]] && exit 0

[[ "$(basename "${file_path}")" != "entrypoint.sh" ]] && exit 0

# Check if the edit touches token-handling or cleanup code.
# Aggregate content from Edit (new_string/old_string) and Write (content) tools.
content=""
[[ -n "${TOOL_INPUT_new_string:-}" ]] && content+="${TOOL_INPUT_new_string}"$'\n'
[[ -n "${TOOL_INPUT_old_string:-}" ]] && content+="${TOOL_INPUT_old_string}"$'\n'
[[ -n "${TOOL_INPUT_content:-}" ]] && content+="${TOOL_INPUT_content}"$'\n'
[[ -z "${content}" ]] && exit 0

if printf '%s' "${content}" | grep -qE '(extract_token|get_.*_token|make_jwt|cleanup|PRIVATE_KEY|pem)'; then
  echo "NOTE: This edit touches security-critical token handling code." >&2
  echo "  - Verify extract_token() still validates null/empty responses" >&2
  echo "  - Verify cleanup() subshell isolates fail() from PEM deletion" >&2
  echo "  - Verify PEM is read from GITHUB_APP_PRIVATE_KEY_FILE (bind-mount), copied to tmpfs, then deleted before run.sh" >&2
fi
