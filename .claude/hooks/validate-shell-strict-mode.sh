#!/usr/bin/env bash
# PostToolUse hook: after Edit/Write of a `.sh` file, re-read it from disk
# and warn if `set -Eeuo pipefail` (or equivalent) is missing in the first
# 30 lines. Complements `block-shell-strict-mode-removal.sh`, which only
# inspects Write content and cannot see the rest of the file after an Edit.
# See .claude/rules/02-entrypoint-shell-strict-mode.md

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

case "${file_path}" in
*.sh) ;;
*) exit 0 ;;
esac

head_text="$(head -30 "${file_path}")"

matches() {
  printf '%s\n' "${head_text}" | grep -qE "$1"
}

has_E='no' has_e='no' has_u='no' has_pipefail='no'
matches 'set[[:space:]]+-[a-zA-Z]*E[a-zA-Z]*' && has_E='yes'
matches 'set[[:space:]]+-o[[:space:]]+errtrace' && has_E='yes'
matches 'set[[:space:]]+-[a-zA-Z]*e[a-zA-Z]*' && has_e='yes'
matches 'set[[:space:]]+-o[[:space:]]+errexit' && has_e='yes'
matches 'set[[:space:]]+-[a-zA-Z]*u[a-zA-Z]*' && has_u='yes'
matches 'set[[:space:]]+-o[[:space:]]+nounset' && has_u='yes'
matches 'set[[:space:]]+-o[[:space:]]+pipefail' && has_pipefail='yes'
matches 'set[[:space:]]+-[a-zA-Z]*o[a-zA-Z]*[[:space:]]+pipefail' && has_pipefail='yes'

missing=()
[[ "${has_E}" == 'yes' ]] || missing+=('-E')
[[ "${has_e}" == 'yes' ]] || missing+=('-e')
[[ "${has_u}" == 'yes' ]] || missing+=('-u')
[[ "${has_pipefail}" == 'yes' ]] || missing+=('-o pipefail')

if [[ ${#missing[@]} -gt 0 ]]; then
  cat >&2 <<MSG
WARNING: ${file_path} no longer declares the full strict-mode flag set in
the first 30 lines. Missing: ${missing[*]}
Add: set -Eeuo pipefail
See .claude/rules/02-entrypoint-shell-strict-mode.md
MSG
fi
