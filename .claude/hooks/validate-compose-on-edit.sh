#!/usr/bin/env bash
# PostToolUse hook: Validate docker-compose.yml after edits

set -euo pipefail

file_path="${TOOL_INPUT_FILE_PATH:-${TOOL_INPUT_file_path:-}}"
[[ -z "${file_path}" ]] && exit 0

basename="$(basename "${file_path}")"
compose_dir="$(dirname "${file_path}")"

if [[ "${basename}" == "docker-compose.yml" || "${basename}" == "docker-compose.yaml" || "${basename}" == "compose.yml" || "${basename}" == "compose.yaml" ]]; then
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    if ! docker compose --project-directory "${compose_dir}" -f "${file_path}" config --quiet 2>/dev/null; then
      echo "WARNING: ${basename} has validation errors" >&2
      docker compose --project-directory "${compose_dir}" -f "${file_path}" config 2>&1 | head -5 >&2
    fi
  fi
fi
