#!/usr/bin/env bash
# Pre-commit / CI guard: enforce the security invariants that previously had
# ONLY client-side Claude hook coverage, so a direct edit by any contributor
# or tool is also caught at commit/PR time:
#   - rule 06: every FROM / image: reference is @sha256: digest-pinned
#   - rule 11: socket-proxy exposes only the minimal Docker API surface
#   - rule 12: runner cap_add is a subset of the documented minimum
#   - rule 13: Dockerfile has no whole-context COPY/ADD or opaque remote ADD
#
# Mirrors the per-rule "Verification" sections and the client-side hooks.
# Usage: check-security-invariants.sh <file>...  (pre-commit passes staged paths)

set -Eeuo pipefail

rc=0
fail() {
  echo "FAIL: $1" >&2
  rc=1
}

for f in "$@"; do
  [[ -f "${f}" ]] || continue
  case "$(basename "${f}")" in
  Dockerfile | *.Dockerfile)
    # rule 06: every FROM (except `scratch`) must carry a digest.
    if printf '%s\n' "$(grep -E '^FROM ' "${f}" || true)" |
      grep -vE '^FROM scratch( |$)' | grep -q '^FROM ' &&
      printf '%s\n' "$(grep -E '^FROM ' "${f}" || true)" |
      grep -vE '^FROM scratch( |$)' | grep -qv '@sha256:'; then
      fail "${f}: a FROM line is missing an @sha256: digest (rule 06)"
    fi
    # rule 13: no whole-context COPY/ADD; no opaque remote ADD.
    if grep -nE '^(COPY|ADD)([[:space:]]+--[a-zA-Z]+=[^[:space:]]+)*[[:space:]]+\./?([[:space:]]|$)' "${f}" |
      grep -qv -- '--from='; then
      fail "${f}: whole-context COPY/ADD is forbidden (rule 13)"
    fi
    if grep -qE '^ADD[[:space:]]+https?://' "${f}"; then
      fail "${f}: opaque remote ADD is forbidden (rule 13)"
    fi
    ;;
  docker-compose.yml | docker-compose.yaml | compose.yml | compose.yaml)
    # rule 06: every image: must be digest-pinned (ignore local build + vars).
    if grep -E '^[[:space:]]*image:[[:space:]]' "${f}" |
      grep -vE 'local/|[$]\{' | grep -qv '@sha256:'; then
      fail "${f}: an image: reference is missing an @sha256: digest (rule 06)"
    fi
    # rule 11: forbidden socket-proxy API surface unless explicitly annotated.
    if grep -nE '^[[:space:]]+(CONTAINERS|EXEC|VOLUMES|NETWORKS|PLUGINS|SECRETS|SWARM|TASKS|SERVICES|NODES|SESSION|SYSTEM):[[:space:]]+(1|true|"1"|"true")' "${f}" |
      grep -qv '# allow-socket-proxy-rule-11'; then
      fail "${f}: socket-proxy Docker API surface widened beyond rule 11"
    fi
    # no-new-privileges is load-bearing: the runner base image ships a
    # setuid-root sudo and the runner user is in the sudo group, so dropping
    # this flag would let a workflow `sudo cat` the root-owned PEM. Require it
    # never disabled, present at least once, AND present in EVERY security_opt
    # block — YAML merge REPLACES security_opt rather than deep-merging it
    # (rule 05), so a per-service override could otherwise drop the flag while
    # the anchor's copy keeps a file-wide grep green (finding N-70).
    if grep -qE 'no-new-privileges:[[:space:]]*"?false' "${f}"; then
      fail "${f}: 'no-new-privileges:false' re-enables setuid escalation (PEM-theft path)"
    fi
    if ! grep -qE 'no-new-privileges:[[:space:]]*"?true' "${f}"; then
      fail "${f}: missing 'no-new-privileges:true' (load-bearing for PEM isolation — setuid sudo in base image)"
    fi
    nnp_bad="$(awk '
      /^[[:space:]]*security_opt:[[:space:]]*\[/ {
        if ($0 !~ /no-new-privileges:[[:space:]]*"?true/) print NR
        next
      }
      /^[[:space:]]*security_opt:[[:space:]]*$/ { in_so=1; has=0; bl=NR; next }
      in_so && /^[[:space:]]*-[[:space:]]/ {
        if ($0 ~ /no-new-privileges:[[:space:]]*"?true/) has=1
        next
      }
      in_so && /^[[:space:]]*#/ { next }
      in_so && /^[[:space:]]*$/ { next }
      in_so { if (!has) print bl; in_so=0 }
      END { if (in_so && !has) print bl }
    ' "${f}")"
    [[ -n "${nnp_bad}" ]] && fail "${f}: a security_opt block omits 'no-new-privileges:true' (per-service override drops PEM isolation; YAML replaces not merges — rule 05/N-70) at line(s): ${nnp_bad//$'\n'/ }"
    # rule 12: runner cap_add must be a subset of the documented minimum.
    bad_caps="$(awk '
      /cap_add:[[:space:]]*$/ { in_cap=1; next }
      in_cap && /^[[:space:]]*-[[:space:]]+[A-Z_]+/ {
        cap=$0; sub(/^[[:space:]]*-[[:space:]]+/, "", cap); sub(/[[:space:]]*(#.*)?$/, "", cap)
        if (cap !~ /^(CHOWN|DAC_OVERRIDE|FOWNER|SETGID|SETUID|KILL)$/ && $0 !~ /# allow-cap-rule-12/) print cap
        next
      }
      in_cap && /^[[:space:]]*[a-zA-Z_]+:/ { in_cap=0 }
      in_cap && /^[^[:space:]-]/ { in_cap=0 }
    ' "${f}")"
    [[ -n "${bad_caps}" ]] && fail "${f}: cap_add beyond rule 12 minimum: ${bad_caps//$'\n'/ }"
    ;;
  esac
done

exit "${rc}"
