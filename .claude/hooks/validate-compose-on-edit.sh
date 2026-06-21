#!/usr/bin/env bash
# PostToolUse hook: Validate docker-compose.yml after edits

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

basename="$(basename "${file_path}")"
compose_dir="$(dirname "${file_path}")"

if [[ "${basename}" == "docker-compose.yml" || "${basename}" == "docker-compose.yaml" || "${basename}" == "compose.yml" || "${basename}" == "compose.yaml" ]]; then
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    if ! docker compose --project-directory "${compose_dir}" -f "${file_path}" config --quiet 2>/dev/null; then
      echo "WARNING: ${basename} has validation errors" >&2
      docker compose --project-directory "${compose_dir}" -f "${file_path}" config 2>&1 | head -5 >&2 || true
    fi
  fi
fi
