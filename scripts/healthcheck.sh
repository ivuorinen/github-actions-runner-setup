#!/usr/bin/env bash
# Container healthcheck. Returns 0 if the GitHub Actions runner listener
# process is alive, 1 otherwise. We anchor on the runner's own binaries
# (`/home/runner/run.sh` or `Runner.Listener` from the actions-runner
# distribution) rather than a substring match like `*run.sh*`, which would
# false-positive on any workflow that happens to spawn a script with
# "run.sh" in its argv.

set -Eeuo pipefail

readonly RUNNER_HOME="/home/runner"

for cmdline in /proc/[0-9]*/cmdline; do
  [[ -r "${cmdline}" ]] || continue
  cmd="$(tr '\0' ' ' <"${cmdline}" 2>/dev/null || true)"
  [[ -z "${cmd}" ]] && continue

  case "${cmd}" in
  # The actions-runner ships its main binary as Runner.Listener; it
  # always lives under /home/runner/bin/ in the upstream image.
  *${RUNNER_HOME}/bin/Runner.Listener*) exit 0 ;;
  # config.sh and run.sh are the runner's bootstrap scripts; both are
  # invoked from /home/runner (set as WORKDIR in the Dockerfile).
  *bash\ ./run.sh* | *${RUNNER_HOME}/run.sh*) exit 0 ;;
  # entrypoint.sh holds the parent shell while the listener is alive.
  # When this is the only match left, we are in the startup window
  # before the listener spawns or right after it exits ahead of cleanup.
  esac
done

exit 1
