#!/usr/bin/env bash
# PreToolUse hook: Block edits to .env files to prevent accidental secret exposure
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

if [[ "${basename}" == ".env" || "${basename}" == .env.* ]]; then
  # Allow .env.example edits
  [[ "${basename}" == ".env.example" ]] && exit 0
  echo "BLOCKED: Cannot edit ${basename} — use .env.example for configuration templates" >&2
  exit 2
fi
