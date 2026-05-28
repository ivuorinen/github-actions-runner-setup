#!/usr/bin/env bash
# PreToolUse hook: enforce .claude/rules/11-socket-proxy-env-minimum.md
# Refuse edits that add CONTAINERS/EXEC/VOLUMES/etc. to socket-proxy's
# environment without the explicit per-line `# allow-socket-proxy-rule-11`
# annotation. The annotation is the documented bypass for operators who
# have accepted the cross-runner-inspection risk in their security model.
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

# Forbidden socket-proxy env vars when set to a truthy value (1/true).
forbidden_re='^[[:space:]]+(CONTAINERS|EXEC|VOLUMES|NETWORKS|PLUGINS|SECRETS|SWARM|TASKS|SERVICES|NODES|SESSION|SYSTEM):[[:space:]]+(1|true|"1"|"true")[[:space:]]*(#.*)?$'

violations="$(printf '%s\n' "${content}" | grep -nE "${forbidden_re}" || true)"
[[ -z "${violations}" ]] && exit 0

# Strip violations that carry the explicit allow annotation.
filtered="$(printf '%s\n' "${violations}" | grep -v '# allow-socket-proxy-rule-11' || true)"
[[ -z "${filtered}" ]] && exit 0

cat >&2 <<MSG
BLOCKED: Enabling the following socket-proxy env var(s) widens the Docker
API surface beyond rule 11's allowed set (IMAGES, BUILD, POST, INFO, PING):

${filtered}

If the workflow truly needs this surface (typical case: \`docker run\`
requires CONTAINERS=1), add an inline annotation on the same line:
  CONTAINERS: 1  # allow-socket-proxy-rule-11: jobs run docker containers
AND document the cross-runner inspection risk in docs/SECURITY.md.
See .claude/rules/11-socket-proxy-env-minimum.md
MSG
exit 2
