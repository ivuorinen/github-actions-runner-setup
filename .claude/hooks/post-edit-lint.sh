#!/usr/bin/env bash
# PostToolUse hook: Run pre-commit linting on edited files
# Triggered after Edit/Write operations

set -euo pipefail

file_path="${TOOL_INPUT_FILE_PATH:-${TOOL_INPUT_file_path:-}}"
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
