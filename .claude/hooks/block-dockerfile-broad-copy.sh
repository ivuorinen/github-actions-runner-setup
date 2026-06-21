#!/usr/bin/env bash
# PreToolUse hook: enforce .claude/rules/13-dockerfile-no-broad-copy.md
# Refuse edits that introduce a whole-context `COPY .` / `COPY ./` /
# `ADD .` / `ADD ./` into the Dockerfile. The .dockerignore is defense-
# in-depth, not a sufficient boundary on its own.
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
Dockerfile | *.Dockerfile) ;;
*) exit 0 ;;
esac

content="$(jq -r '.tool_input.new_string // .tool_input.content // empty' <<<"${hook_input}" 2>/dev/null || true)"
[[ -z "${content}" ]] && exit 0

# Match:
#   COPY . <dest>
#   COPY ./ <dest>
#   COPY [--chown=...] . <dest>
#   COPY [--from=...] . <dest>   (would be unusual to flag — multi-stage)
#   ADD . <dest>
#   ADD ./ <dest>
#   ADD https://... <dest>       (opaque remote, separate concern)
broad_copy_re='^(COPY|ADD)([[:space:]]+--[a-zA-Z]+=[^[:space:]]+)*[[:space:]]+\./?([[:space:]]|$)'
remote_add_re='^ADD[[:space:]]+https?://'

violations="$(printf '%s\n' "${content}" | grep -nE "${broad_copy_re}" || true)"
remote="$(printf '%s\n' "${content}" | grep -nE "${remote_add_re}" || true)"

# Multi-stage COPY --from=<stage> . is acceptable — it copies the WHOLE
# build stage, not the host context. Filter those out.
violations="$(printf '%s\n' "${violations}" | grep -v -- '--from=' || true)"

if [[ -z "${violations}" && -z "${remote}" ]]; then exit 0; fi

cat >&2 <<MSG
BLOCKED: Dockerfile uses a forbidden whole-context COPY/ADD shape.

${violations:+Whole-context copies:
${violations}
}${remote:+Opaque remote ADD (rule 13 also blocks unverified network fetches):
${remote}
}
Use per-file or per-subdirectory COPY instead:
  COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
See .claude/rules/13-dockerfile-no-broad-copy.md
MSG
exit 2
