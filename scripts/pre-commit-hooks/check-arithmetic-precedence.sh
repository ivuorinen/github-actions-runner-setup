#!/usr/bin/env bash
# Pre-commit local hook: detect the bash arithmetic operator-precedence trap
# `(a OP b == c)` where OP is `&`, `|`, or `^`. See
# .claude/rules/09-arithmetic-precedence-bash.md

set -Eeuo pipefail

rc=0
for f in "$@"; do
  [[ -f "${f}" ]] || continue
  if grep -nE '\(\([^()]*[[:space:]][&|^][[:space:]][^()]*(==|!=)' "${f}"; then
    echo "FAIL ${f}: arithmetic precedence trap detected." >&2
    echo "See .claude/rules/09-arithmetic-precedence-bash.md" >&2
    rc=1
  fi
done
exit "${rc}"
