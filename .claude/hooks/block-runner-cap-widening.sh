#!/usr/bin/env bash
# PreToolUse hook: enforce .claude/rules/12-runner-cap-add-minimal.md
# Refuse edits that add Linux capabilities beyond the documented minimum
# (CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID, KILL) to any runner
# service's cap_add block without the explicit per-line
# `# allow-cap-rule-12: <reason>` annotation.
#
# We detect new caps appearing in a `cap_add:` neighbourhood. We do NOT
# parse the YAML deeply; the simpler shape — a `- CAP_NAME` line near a
# `cap_add:` line — is good enough as a guardrail.
#
# Exit code 2 = block the tool call.

set -Eeuo pipefail

# Claude Code delivers the tool payload as JSON on stdin (NOT environment
# variables). See https://code.claude.com/docs/en/hooks.
if ! command -v jq >/dev/null 2>&1; then
  echo "BLOCKED: jq not found; $(basename "$0") cannot enforce; failing closed. Install jq." >&2
  exit 2
fi
hook_input="$(cat)"
file_path="$(jq -r '.tool_input.file_path // empty' <<<"${hook_input}" 2>/dev/null || true)"
[[ -z "${file_path}" ]] && exit 0

basename="$(basename "${file_path}")"
case "${basename}" in
docker-compose.yml | docker-compose.yaml | compose.yml | compose.yaml) ;;
*) exit 0 ;;
esac

content="$(jq -r '.tool_input.new_string // .tool_input.content // empty' <<<"${hook_input}" 2>/dev/null || true)"
[[ -z "${content}" ]] && exit 0

# Allowed caps per rule 12. socket-proxy already cap_drops ALL with no
# cap_add — different rule. We focus on the runner services' cap_add.
allowed='CHOWN|DAC_OVERRIDE|FOWNER|SETGID|SETUID|KILL'

# Walk the content line by line, tracking whether we are inside a
# cap_add: block. A new top-level key or de-indent ends the block.
violations="$(printf '%s\n' "${content}" | awk -v allowed="${allowed}" '
  /cap_add:[[:space:]]*$/ { in_cap=1; next }
  in_cap && /^[[:space:]]*-[[:space:]]+[A-Z_]+/ {
    # Extract the cap name (after the dash).
    cap=$0
    sub(/^[[:space:]]*-[[:space:]]+/, "", cap)
    sub(/[[:space:]]*(#.*)?$/, "", cap)
    if (cap !~ "^(" allowed ")$") {
      # Check for the bypass annotation on the SAME line.
      if ($0 !~ /# allow-cap-rule-12/) {
        printf "line %d: %s\n", NR, $0
      }
    }
    next
  }
  in_cap && /^[[:space:]]*[a-zA-Z_]+:/ { in_cap=0 }
  in_cap && /^[^[:space:]-]/ { in_cap=0 }
')"

[[ -z "${violations}" ]] && exit 0

cat >&2 <<MSG
BLOCKED: cap_add includes capability/capabilities beyond the documented
minimum (rule 12: CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID, KILL):

${violations}

If a workflow genuinely needs the capability, add the annotation on the
same line:
  - SYS_PTRACE  # allow-cap-rule-12: profiling action needs ptrace
AND document the runtime exposure in docs/SECURITY.md.
See .claude/rules/12-runner-cap-add-minimal.md
MSG
exit 2
