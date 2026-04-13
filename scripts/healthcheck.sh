#!/usr/bin/env bash
set -Eeuo pipefail

if pgrep -f "Runner.Listener|run.sh|config.sh" >/dev/null 2>&1; then
  exit 0
fi

exit 1
