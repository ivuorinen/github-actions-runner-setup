#!/usr/bin/env bash
# PreToolUse hook: Block edits to .env files to prevent accidental secret exposure
# Exit code 2 = block the tool call

set -Eeuo pipefail

file_path="${TOOL_INPUT_FILE_PATH:-${TOOL_INPUT_file_path:-}}"
[[ -z "${file_path}" ]] && exit 0

basename="$(basename "${file_path}")"

if [[ "${basename}" == ".env" || "${basename}" == .env.* ]]; then
  # Allow .env.example edits
  [[ "${basename}" == ".env.example" ]] && exit 0
  echo "BLOCKED: Cannot edit ${basename} — use .env.example for configuration templates" >&2
  exit 2
fi
