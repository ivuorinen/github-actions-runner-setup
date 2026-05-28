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
  # Version aligned with .pre-commit-config.yaml and Makefile lint-docker;
  # Renovate keeps the tag + digest in lockstep.
  if ! docker run --rm -i \
    hadolint/hadolint:v2.14.0@sha256:27086352fd5e1907ea2b934eb1023f217c5ae087992eb59fde121dce9c9ff21e \
    hadolint - <"${file_path}" 2>/dev/null; then
    echo "WARNING: hadolint (containerized) flagged issues in ${basename}" >&2
  fi
fi
