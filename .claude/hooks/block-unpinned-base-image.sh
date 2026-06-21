#!/usr/bin/env bash
# PreToolUse hook: every FROM in Dockerfile and every `image:` reference in
# compose files must include an @sha256: digest. See
# .claude/rules/06-base-image-must-be-digest-pinned.md
# Exit code 2 = block the tool call

set -Eeuo pipefail

# Claude Code delivers the tool payload as JSON on stdin (NOT environment
# variables). See https://code.claude.com/docs/en/hooks.
if ! command -v jq >/dev/null 2>&1; then
  echo "WARNING: jq not found; $(basename "$0") enforcement skipped. Install jq." >&2
  exit 0
fi
hook_input="$(cat)"
file_path="$(jq -r '.tool_input.file_path // empty' <<<"${hook_input}" 2>/dev/null || true)"
[[ -z "${file_path}" ]] && exit 0

basename="$(basename "${file_path}")"

content="$(jq -r '.tool_input.new_string // .tool_input.content // empty' <<<"${hook_input}" 2>/dev/null || true)"
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
