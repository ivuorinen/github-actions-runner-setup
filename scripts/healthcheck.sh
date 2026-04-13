#!/usr/bin/env bash
set -Eeuo pipefail

for cmdline in /proc/[0-9]*/cmdline; do
  [[ -r "${cmdline}" ]] || continue
  cmd="$(tr '\0' ' ' <"${cmdline}" 2>/dev/null || true)"
  case "${cmd}" in
    *Runner.Listener* | *run.sh*)
      exit 0
      ;;
  esac
done

exit 1
