#!/usr/bin/env bash
# PreToolUse hook: Block force-push variants and destructive resets against
# main/master branches. Covers:
#   - git push ... --force            (without --force-with-lease)
#   - git push ... -f
#   - git push ... +main / +master    (refspec-prefix force push)
#   - git push ... +refs/heads/main   (long-form refspec force push)
#   - git reset --hard while on main/master
#   - git update-ref -d refs/heads/main
# Exit code 2 = block the tool call

set -Eeuo pipefail

# Claude Code delivers the tool payload as JSON on stdin (NOT environment
# variables). See https://code.claude.com/docs/en/hooks.
if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED: jq not found; $(basename "$0") cannot enforce; failing closed. Install jq." >&2
  exit 2
fi
hook_input="$(cat)"
command="$(jq -r '.tool_input.command // empty' <<<"${hook_input}" 2>/dev/null || true)"
[[ -z "${command}" ]] && exit 0

# Pattern A: explicit --force / -f flag (excluding --force-with-lease,
# the safe alternative). --force-with-lease ends in `-` after --force,
# so the negative lookahead `[^-]` rejects it.
flag_force_re='git[[:space:]]+push.*(--force($|[^-])|[[:space:]]-f($|[^a-zA-Z]))'

# Pattern B: refspec-prefix force push. A leading `+` on a refspec means
# "allow non-fast-forward" against the destination ref. Shapes covered:
#   +main                  destination=main, no explicit source
#   +master
#   +refs/heads/main
#   +HEAD:main             destination=main, source=HEAD
#   +abc1234:main          destination=main, source=abc1234
#   +HEAD:refs/heads/main
# The `(...)?:` group makes the source-then-colon optional so `+main`
# (no `:`) is caught too.
refspec_force_target_re='git[[:space:]]+push[^|;]*[[:space:]]\+([^[:space:]:]+:)?(refs/heads/)?(main|master)([[:space:]]|$|:)'

# Pattern C: branch-delete via push refspec — empty source means delete.
#   git push origin :main
#   git push origin :refs/heads/master
push_colon_delete_re='git[[:space:]]+push[^|;]*[[:space:]]:(refs/heads/)?(main|master)([[:space:]]|$|:)'

# Pattern D: --delete flag form. Branch can appear after the remote name
# (typical) or directly (rare). Accept both.
#   git push --delete origin main
#   git push origin --delete main
#   git push --delete origin refs/heads/master
push_delete_flag_re='git[[:space:]]+push[^|;]*--delete[^|;]*[[:space:]](refs/heads/)?(main|master)([[:space:]]|$|:)'

if [[ "${command}" =~ ${flag_force_re} ]] || [[ "${command}" =~ ${refspec_force_target_re} ]]; then
  if [[ "${command}" =~ ${refspec_force_target_re} ]] ||
    [[ "${command}" =~ (^|[[:space:]:/])(refs/heads/)?(main|master)($|[[:space:]]) ]]; then
    echo "BLOCKED: Force push to main/master is not allowed (matched: ${BASH_REMATCH[0]})" >&2
    exit 2
  fi
fi

if [[ "${command}" =~ ${push_colon_delete_re} ]] || [[ "${command}" =~ ${push_delete_flag_re} ]]; then
  echo "BLOCKED: Deleting remote main/master via push is not allowed (matched: ${BASH_REMATCH[0]})" >&2
  exit 2
fi

# Pattern D: destructive resets while on main/master.
if [[ "${command}" =~ git[[:space:]]+reset[[:space:]]+--hard ]] &&
  [[ "$(git branch --show-current 2>/dev/null || true)" =~ ^(main|master)$ ]]; then
  echo "BLOCKED: git reset --hard on main/master is not allowed" >&2
  exit 2
fi

# Pattern E: deleting the main/master ref outright via update-ref.
if [[ "${command}" =~ git[[:space:]]+update-ref[[:space:]]+-d[[:space:]]+refs/heads/(main|master) ]]; then
  echo "BLOCKED: deleting refs/heads/main or refs/heads/master is not allowed" >&2
  exit 2
fi
