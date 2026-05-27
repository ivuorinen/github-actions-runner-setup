#!/usr/bin/env bash
# Pre-commit local hook: refuse to allow /var/run/docker.sock to be mounted
# into any service other than socket-proxy. See
# .claude/rules/04-docker-socket-never-in-runner.md
#
# Compose service names live at exactly 2 spaces of indentation under the
# top-level `services:` mapping. Anything more indented is a sub-key of a
# service (volumes:, environment:, etc.) and must not be treated as a
# service name.

set -Eeuo pipefail

rc=0
for f in "$@"; do
  [[ -f "${f}" ]] || continue
  violations="$(awk '
    # Detect entry into the services: block (top-level key).
    /^services:[[:space:]]*$/ { in_services = 1; current = ""; next }

    # A new top-level key ends the services block.
    /^[-a-zA-Z0-9_]+:[[:space:]]*$/ && !/^services:/ { in_services = 0 }

    # Inside services:, a service name is exactly two spaces of indent
    # followed by `name:`.
    in_services && /^  [-a-zA-Z0-9_]+:[[:space:]]*$/ {
      gsub(/[[:space:]:]/, "", $0); current = $0
    }

    # Match docker.sock bind mounts and report any that are not in
    # socket-proxy. `current` will be "" outside services: (e.g. top-
    # level `volumes:`); we treat that as a non-violation because such
    # mounts cannot apply to a runner service.
    in_services && /\/var\/run\/docker\.sock:\/var\/run\/docker\.sock/ {
      if (current != "" && current != "socket-proxy") {
        printf "%s:%d: service=%s\n", FILENAME, NR, current
      }
    }
  ' "${f}")"
  if [[ -n "${violations}" ]]; then
    printf '%s\n' "${violations}" >&2
    echo "FAIL: docker.sock mounted outside socket-proxy." >&2
    echo "See .claude/rules/04-docker-socket-never-in-runner.md" >&2
    rc=1
  fi
done
exit "${rc}"
