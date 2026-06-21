#!/usr/bin/env bash
# PreToolUse hook: every .sh file must declare strict mode (`set -Eeuo pipefail`
# or an equivalent combination of long-form `set -o` directives) within the
# first 30 lines. See .claude/rules/02-entrypoint-shell-strict-mode.md
#
# We only fire on Write of a complete file. Edit operations are not checked
# here because the new_string payload field is a partial diff and we cannot tell
# whether the rest of the file still declares strict mode. The PostToolUse
# companion hook `validate-shell-strict-mode.sh` reads the on-disk file and
# warns when strict mode is missing after an Edit.
#
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

case "${file_path}" in
*.sh) ;;
*) exit 0 ;;
esac

content="$(jq -r '.tool_input.content // empty' <<<"${hook_input}" 2>/dev/null || true)"
[[ -z "${content}" ]] && exit 0

head_text="$(printf '%s\n' "${content}" | head -30)"

# For each required flag, accept either the short-form cluster
# (`set -…X…`) or the long-form `set -o <name>` line. Regex greediness +
# backtracking handles letter ordering: in `set -Eeuo`, the regex
# `set[[:space:]]+-[a-zA-Z]*e[a-zA-Z]*` matches because `[a-zA-Z]*` can
# give up the `e` if needed.
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
[[ "${has_E}" == 'yes' ]] || missing+=('-E (errtrace)')
[[ "${has_e}" == 'yes' ]] || missing+=('-e (errexit)')
[[ "${has_u}" == 'yes' ]] || missing+=('-u (nounset)')
[[ "${has_pipefail}" == 'yes' ]] || missing+=('-o pipefail')

if [[ ${#missing[@]} -gt 0 ]]; then
  cat >&2 <<MSG
BLOCKED: Shell script ${file_path} is missing required strict-mode flag(s):
  ${missing[*]}

Declare them within the first 30 lines, canonically as:
  set -Eeuo pipefail

See .claude/rules/02-entrypoint-shell-strict-mode.md
MSG
  exit 2
fi
