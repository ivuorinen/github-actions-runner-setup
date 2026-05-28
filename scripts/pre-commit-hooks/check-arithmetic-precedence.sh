#!/usr/bin/env bash
# Pre-commit local hook: detect the bash arithmetic operator-precedence trap
# where a bitwise operator (& | ^) and an equality comparison (== !=) live
# at the same paren depth inside a bash arithmetic expansion. See
# .claude/rules/09-arithmetic-precedence-bash.md
#
# Whitespace is NOT required around the bitwise operator: the trap applies
# to `a&b==c` and `a & b == c` alike. The regex therefore uses `.*` between
# the arith opener and the bitwise op, and `[^)]*` (no closing paren) between
# the bitwise op and the comparison. A correctly parenthesised expression
# such as `(((8#mode) & 077) == 0)` has a `)` between the `&` and the `==`,
# which `[^)]*` cannot span, so it is not flagged.

set -Eeuo pipefail

# Build the regex in a variable so the literal does not need to appear
# inline alongside narrative comments that would otherwise share the shape.
trap_re="\(\(.*[&|^][^)]*(==|!=)"

rc=0
for f in "$@"; do
  [[ -f "${f}" ]] || continue
  # Skip files that exist specifically to document or detect the pattern.
  # Patterns allow both absolute paths (CI invocation) and repo-relative
  # paths (pre-commit invocation from the repo root).
  case "${f}" in
  *.claude/rules/09-arithmetic-precedence-bash.md) continue ;;
  *scripts/pre-commit-hooks/check-arithmetic-precedence.sh) continue ;;
  *.claude/hooks/validate-entrypoint-arithmetic.sh) continue ;;
  esac
  if grep -nE "${trap_re}" "${f}"; then
    echo "FAIL ${f}: arithmetic precedence trap detected." >&2
    echo "See .claude/rules/09-arithmetic-precedence-bash.md" >&2
    rc=1
  fi
done
exit "${rc}"
