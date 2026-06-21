#!/usr/bin/env bash
# PostToolUse hook: catch bash arithmetic with bitwise + comparison that is
# missing protective inner parens. See
# .claude/rules/09-arithmetic-precedence-bash.md
#
# Pattern in scope (described in words to avoid the regex matching this
# very file): a bash arithmetic expansion opener, followed by an expression
# that uses a bitwise operator and an equality comparison at the SAME paren
# depth — meaning no closing paren between the bitwise operator and the
# comparison. That is the precedence trap that broke the PEM mode check
# (N-1) before the original fix.
#
# Whitespace is NOT required around the bitwise operator: the bug applies
# equally to `a&b==c` and `a & b == c`, so we use `.*` between the opener
# and the bitwise op and `[^)]*` (NO closing paren) between the bitwise op
# and the comparison.

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

# Skip files that exist specifically to document or detect this pattern.
# Their comments and regex strings legitimately contain the trap shape.
# Patterns allow both absolute paths (PostToolUse passes absolute) and
# repo-relative paths (CI or manual invocation).
case "${file_path}" in
*.claude/rules/09-arithmetic-precedence-bash.md) exit 0 ;;
*scripts/pre-commit-hooks/check-arithmetic-precedence.sh) exit 0 ;;
*.claude/hooks/validate-entrypoint-arithmetic.sh) exit 0 ;;
esac

# Build the regex from pieces so this hook does not match itself when
# scanning its own siblings. The literal we want is:
#   bash-arith-open . any . bitwise . non-close-paren . equality
arith_open='\('"'"
arith_open="\(\("
trap_re="${arith_open}.*[&|^][^)]*(==|!=)"

suspects="$(grep -nE "${trap_re}" "${file_path}" || true)"

if [[ -n "${suspects}" ]]; then
  cat >&2 <<MSG
WARNING: ${file_path} contains arithmetic that may have an operator-
precedence bug. In bash, == binds tighter than & | ^, so an expression
like a-AMP-b-EQ-c at the top level of a bash arithmetic context parses
as a-AMP-(b-EQ-c). Wrap the bitwise sub-expression in its own parens.

Suspicious lines:
${suspects}

See .claude/rules/09-arithmetic-precedence-bash.md
MSG
fi
