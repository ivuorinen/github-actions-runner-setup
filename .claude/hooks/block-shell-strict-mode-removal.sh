#!/usr/bin/env bash
# PreToolUse hook: every .sh file must keep `set -Eeuo pipefail`. See
# .claude/rules/02-entrypoint-shell-strict-mode.md
# Exit code 2 = block the tool call

set -Eeuo pipefail

file_path="${TOOL_INPUT_FILE_PATH:-${TOOL_INPUT_file_path:-}}"
[[ -z "${file_path}" ]] && exit 0

case "${file_path}" in
*.sh) ;;
*) exit 0 ;;
esac

# For Write, the entire new file is in TOOL_INPUT_content. For Edit, the new
# content is in TOOL_INPUT_new_string and is a partial — we cannot tell from
# a partial whether the file still has `set -Eeuo pipefail` somewhere else,
# so we only block on Write of a full file that omits the directive.
content="${TOOL_INPUT_content:-}"
[[ -z "${content}" ]] && exit 0

if ! printf '%s\n' "${content}" | head -20 | grep -qE 'set[[:space:]]+-(E[a-z]*e[a-z]*|.*-o[[:space:]]+pipefail)'; then
  cat >&2 <<MSG
BLOCKED: Shell script ${file_path} must enable strict mode within the
first 20 lines: \`set -Eeuo pipefail\`. See
.claude/rules/02-entrypoint-shell-strict-mode.md
MSG
  exit 2
fi
