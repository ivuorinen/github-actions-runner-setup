#!/usr/bin/env bash
# PostToolUse hook: Run pre-commit linting on edited files
# Triggered after Edit/Write operations

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

# Determine which pre-commit hooks to run based on file type
case "${file_path}" in
*.sh)
  pre-commit run shfmt --files "${file_path}" || true
  pre-commit run shellcheck --files "${file_path}" || true
  ;;
*.yml | *.yaml)
  pre-commit run yamllint --files "${file_path}" || true
  ;;
*.md)
  pre-commit run markdownlint --files "${file_path}" || true
  ;;
esac
