#!/usr/bin/env bash
# PreToolUse hook: Block force push to main/master branches
# Exit code 2 = block the tool call

set -euo pipefail

command="${TOOL_INPUT_command:-}"
[[ -z "${command}" ]] && exit 0

# Check for force push patterns targeting main/master
# Match --force but not --force-with-lease (the safe alternative)
# Match -f at end of string or followed by non-identifier char
if [[ "${command}" =~ git\ push.*--force($|[^-]) ]] || [[ "${command}" =~ git\ push.*\ -f($|[^a-z]) ]]; then
  if [[ "${command}" =~ (main|master) ]]; then
    echo "BLOCKED: Force push to main/master is not allowed" >&2
    exit 2
  fi
fi

# Also block git reset --hard on main/master
if [[ "${command}" =~ git\ reset\ --hard ]] && [[ "$(git branch --show-current 2>/dev/null)" =~ ^(main|master)$ ]]; then
  echo "BLOCKED: git reset --hard on main/master is not allowed" >&2
  exit 2
fi
