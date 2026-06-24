#!/usr/bin/env bash
# PostToolUse hook: Warn when editing security-critical token handling in entrypoint.sh

set -Eeuo pipefail

# Claude Code delivers the tool payload as JSON on stdin (NOT environment
# variables). See https://code.claude.com/docs/en/hooks.
if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: jq not found; $(basename "$0") skipped. Install jq." >&2
  exit 0
fi
hook_input="$(cat)"
file_path="$(jq -r '.tool_input.file_path // empty' <<<"${hook_input}" 2>/dev/null || true)"
[[ -z "${file_path}" ]] && exit 0

[[ "$(basename "${file_path}")" != "entrypoint.sh" ]] && exit 0

# Check if the edit touches token-handling or cleanup code.
# Aggregate content from Edit (new_string/old_string) and Write (content) tools.
content=""
new_string="$(jq -r '.tool_input.new_string // empty' <<<"${hook_input}" 2>/dev/null || true)"
old_string="$(jq -r '.tool_input.old_string // empty' <<<"${hook_input}" 2>/dev/null || true)"
write_content="$(jq -r '.tool_input.content // empty' <<<"${hook_input}" 2>/dev/null || true)"
[[ -n "${new_string}" ]] && content+="${new_string}"$'\n'
[[ -n "${old_string}" ]] && content+="${old_string}"$'\n'
[[ -n "${write_content}" ]] && content+="${write_content}"$'\n'
[[ -z "${content}" ]] && exit 0

if printf '%s' "${content}" | grep -qE '(extract_token|get_.*_token|make_jwt|cleanup|PRIVATE_KEY|pem)'; then
  echo "NOTE: This edit touches security-critical token handling code." >&2
  echo "  - Verify extract_token() still validates null/empty responses" >&2
  echo "  - Verify cleanup() subshell isolates fail() from remaining cleanup steps" >&2
  echo "  - Verify PEM handling via GITHUB_APP_PRIVATE_KEY_FILE does not leave sensitive material unexpectedly persisted or exposed before run.sh" >&2
fi
