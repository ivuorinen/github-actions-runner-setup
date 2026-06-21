#!/usr/bin/env bash
# PostToolUse hook: run hadolint on Dockerfile after edits, if available.

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
