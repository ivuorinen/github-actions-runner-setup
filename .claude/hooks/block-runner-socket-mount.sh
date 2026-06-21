#!/usr/bin/env bash
# PreToolUse hook: prevent bind-mounting /var/run/docker.sock into runner-*
# services. Only the socket-proxy service may mount the raw host socket.
# See .claude/rules/04-docker-socket-never-in-runner.md
#
# Detects both compose volume syntaxes:
#   short form:  - /var/run/docker.sock:/var/run/docker.sock[:ro]
#   long form:   - source: /var/run/docker.sock
#                  target: ...
#
# In Write mode the full compose file is in the payload; we parse it with
# awk and identify which service owns each socket mount, so the mere
# presence of the string "socket-proxy" elsewhere in the file does not
# unblock a mount that actually belongs to a runner.
#
# In Edit mode the payload is a partial snippet; we fall back to a
# heuristic: the snippet is allowed only if it contains the literal
# socket-proxy service-header line (`^  socket-proxy:`). A comment that
# merely mentions socket-proxy does not unblock.
#
# Exit code 2 = block the tool call.

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

basename="$(basename "${file_path}")"
case "${basename}" in
docker-compose.yml | docker-compose.yaml | compose.yml | compose.yaml) ;;
*) exit 0 ;;
esac

content="$(jq -r '.tool_input.new_string // .tool_input.content // empty' <<<"${hook_input}" 2>/dev/null || true)"
[[ -z "${content}" ]] && exit 0

short_form_re='/var/run/docker\.sock[[:space:]]*:[[:space:]]*/var/run/docker\.sock'
long_form_re='^[[:space:]]*source:[[:space:]]*[\"'\'']?/var/run/docker\.sock'

if ! printf '%s\n' "${content}" | grep -qE "${short_form_re}" &&
  ! printf '%s\n' "${content}" | grep -qE "${long_form_re}"; then
  exit 0
fi

block_with_message() {
  cat >&2 <<'MSG'
BLOCKED: Detected /var/run/docker.sock bind-mount in a non-socket-proxy
service. Runner containers must reach Docker via DOCKER_HOST=tcp://socket-proxy:2375.
See .claude/rules/04-docker-socket-never-in-runner.md
MSG
  exit 2
}

# Detect whether this looks like a full compose file (has `services:` at top
# level) or a partial edit snippet.
if printf '%s\n' "${content}" | grep -qE '^services:[[:space:]]*$'; then
  # Full-file mode: parse and attribute each socket-mount line to a service.
  # The same algorithm used by scripts/pre-commit-hooks/check-no-docker-sock-in-runner.sh.
  violations="$(printf '%s\n' "${content}" | awk '
    /^services:[[:space:]]*$/ { in_services=1; current=""; next }
    /^[-a-zA-Z0-9_]+:[[:space:]]*$/ && !/^services:/ { in_services=0; current="" }
    in_services && /^  [-a-zA-Z0-9_]+:[[:space:]]*$/ {
      s=$0; gsub(/[[:space:]:]/, "", s); current=s
    }
    /\/var\/run\/docker\.sock/ {
      if (current != "socket-proxy") {
        printf "line %d service=%s\n", NR, (current == "" ? "(unknown)" : current)
      }
    }
  ')"
  if [[ -n "${violations}" ]]; then
    printf '%s\n' "${violations}" >&2
    block_with_message
  fi
  exit 0
fi

# Partial-edit mode: only allow if the snippet itself includes the
# literal socket-proxy service header (2-space indent + name + colon).
# A free-form comment mentioning the proxy is not enough.
if printf '%s\n' "${content}" | grep -qE '^  socket-proxy:[[:space:]]*$'; then
  exit 0
fi

block_with_message
