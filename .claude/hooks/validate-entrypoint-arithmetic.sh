#!/usr/bin/env bash
# PostToolUse hook: catch bash arithmetic with bitwise + comparison that is
# missing protective inner parens. See
# .claude/rules/09-arithmetic-precedence-bash.md

set -Eeuo pipefail

file_path="${TOOL_INPUT_FILE_PATH:-${TOOL_INPUT_file_path:-}}"
[[ -z "${file_path}" ]] && exit 0
[[ ! -f "${file_path}" ]] && exit 0

case "${file_path}" in
*.sh) ;;
*) exit 0 ;;
esac

# Look for arithmetic expressions where a bitwise operator is immediately
# followed by an equality comparison without a protecting paren around the
# mask. Same shape applies to & | ^ vs == !=. The example case is below,
# split across two strings so this comment does not trip the grep itself.
# Bad pattern:  ((  <expr> SPACE BITWISE SPACE <mask> SPACE COMPARE <value>  ))
# Bad example:  see scripts/entrypoint.sh pre-fix; preserved in
#               .claude/rules/09-arithmetic-precedence-bash.md
suspects="$(grep -nE '\(\([^()]*[[:space:]][&|^][[:space:]][^()]*(==|!=)' "${file_path}" || true)"

if [[ -n "${suspects}" ]]; then
  cat >&2 <<MSG
WARNING: ${file_path} contains arithmetic that may have an operator-
precedence bug. In bash, \`==\` binds tighter than \`& | ^\`, so
\`(a & b == c)\` parses as \`a & (b == c)\`. Wrap the bitwise part:
\`((a & b) == c)\`.

Lines:
${suspects}

See .claude/rules/09-arithmetic-precedence-bash.md
MSG
fi
