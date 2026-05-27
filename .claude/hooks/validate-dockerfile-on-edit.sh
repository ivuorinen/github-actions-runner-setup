#!/usr/bin/env bash
# PostToolUse hook: run hadolint on Dockerfile after edits, if available.

set -Eeuo pipefail

file_path="${TOOL_INPUT_FILE_PATH:-${TOOL_INPUT_file_path:-}}"
[[ -z "${file_path}" ]] && exit 0
[[ ! -f "${file_path}" ]] && exit 0

basename="$(basename "${file_path}")"
case "${basename}" in
Dockerfile | *.Dockerfile) ;;
*) exit 0 ;;
esac

if command -v hadolint >/dev/null 2>&1; then
  if ! hadolint "${file_path}"; then
    echo "WARNING: hadolint flagged issues in ${basename} — review above" >&2
  fi
elif command -v docker >/dev/null 2>&1; then
  # Fall back to the official hadolint container if a local binary is absent.
  # Pinned to a digest so this hook stays reproducible.
  if ! docker run --rm -i \
    hadolint/hadolint:v2.12.0@sha256:7dba9a9f1a0350f6d021fb2f6f88900998a4fb0aaf8e4330aa8c38544f04db42 \
    hadolint - <"${file_path}" 2>/dev/null; then
    echo "WARNING: hadolint (containerized) flagged issues in ${basename}" >&2
  fi
fi
