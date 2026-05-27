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
# Exit code 2 = block the tool call.

set -Eeuo pipefail

file_path="${TOOL_INPUT_FILE_PATH:-${TOOL_INPUT_file_path:-}}"
[[ -z "${file_path}" ]] && exit 0

basename="$(basename "${file_path}")"
case "${basename}" in
docker-compose.yml | docker-compose.yaml | compose.yml | compose.yaml) ;;
*) exit 0 ;;
esac

content="${TOOL_INPUT_new_string:-${TOOL_INPUT_content:-}}"
[[ -z "${content}" ]] && exit 0

# Detect either the short-form bind or the long-form source: clause.
has_short_form() {
  printf '%s\n' "$1" | grep -qE '/var/run/docker\.sock[[:space:]]*:[[:space:]]*/var/run/docker\.sock'
}

has_long_form() {
  printf '%s\n' "$1" | grep -qE '^[[:space:]]*source:[[:space:]]*[\"'\'']?/var/run/docker\.sock'
}

if ! has_short_form "${content}" && ! has_long_form "${content}"; then
  exit 0
fi

# At this point a socket mount appears in the edit. Allow it only if the
# block clearly belongs to socket-proxy. We detect this by requiring the
# string "socket-proxy" in the same content block.
if printf '%s\n' "${content}" | grep -qE 'socket-proxy'; then
  exit 0
fi

cat >&2 <<'MSG'
BLOCKED: Detected /var/run/docker.sock bind-mount in a non-socket-proxy
service. Runner containers must reach Docker via DOCKER_HOST=tcp://socket-proxy:2375.
See .claude/rules/04-docker-socket-never-in-runner.md
MSG
exit 2
