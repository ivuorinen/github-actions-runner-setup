#!/usr/bin/env bash
# PreToolUse hook: every FROM in Dockerfile and every `image:` reference in
# compose files must include an @sha256: digest. See
# .claude/rules/06-base-image-must-be-digest-pinned.md
# Exit code 2 = block the tool call

set -Eeuo pipefail

file_path="${TOOL_INPUT_FILE_PATH:-${TOOL_INPUT_file_path:-}}"
[[ -z "${file_path}" ]] && exit 0

basename="$(basename "${file_path}")"

content="${TOOL_INPUT_new_string:-${TOOL_INPUT_content:-}}"
[[ -z "${content}" ]] && exit 0

check_unpinned() {
  local pattern="$1"
  local label="$2"
  local matches
  matches="$(printf '%s\n' "${content}" | grep -E "${pattern}" | grep -v '@sha256:' || true)"
  if [[ -n "${matches}" ]]; then
    echo "BLOCKED: ${label} reference is missing @sha256: digest pin:" >&2
    printf '%s\n' "${matches}" >&2
    echo "See .claude/rules/06-base-image-must-be-digest-pinned.md" >&2
    exit 2
  fi
}

case "${basename}" in
Dockerfile | *.Dockerfile)
  # Allow `FROM scratch` and `FROM --platform=... <name> AS stage` only
  # if the source name itself is digest-pinned. The grep below intentionally
  # excludes `FROM scratch` because scratch has no image to pin.
  filtered="$(printf '%s\n' "${content}" | grep -E '^FROM ' | grep -vE '^FROM scratch( |$)' || true)"
  if [[ -n "${filtered}" ]]; then
    unpinned="$(printf '%s\n' "${filtered}" | grep -v '@sha256:' || true)"
    if [[ -n "${unpinned}" ]]; then
      echo "BLOCKED: Dockerfile FROM line is missing @sha256: digest pin:" >&2
      printf '%s\n' "${unpinned}" >&2
      echo "See .claude/rules/06-base-image-must-be-digest-pinned.md" >&2
      exit 2
    fi
  fi
  ;;
docker-compose.yml | docker-compose.yaml | compose.yml | compose.yaml)
  # Match `image: foo:bar` but ignore comments and our local build tags
  # of the form `local/...` which are produced by docker compose build.
  filtered="$(printf '%s\n' "${content}" | grep -E '^[[:space:]]*image:[[:space:]]' | grep -vE 'local/|[$]\{' || true)"
  if [[ -n "${filtered}" ]]; then
    unpinned="$(printf '%s\n' "${filtered}" | grep -v '@sha256:' || true)"
    if [[ -n "${unpinned}" ]]; then
      echo "BLOCKED: compose image reference is missing @sha256: digest pin:" >&2
      printf '%s\n' "${unpinned}" >&2
      echo "See .claude/rules/06-base-image-must-be-digest-pinned.md" >&2
      exit 2
    fi
  fi
  ;;
*)
  exit 0
  ;;
esac
