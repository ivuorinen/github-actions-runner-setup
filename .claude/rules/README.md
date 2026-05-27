# .claude/rules/

Rules that constrain how Claude Code modifies this repository. Each rule is a
standalone markdown file; the title is the rule, and the body is the rationale
and how to verify compliance. Claude reads these as project memory.

## Index

- `01-pem-must-be-root-mode-600.md` — host PEM file ownership and permissions
- `02-entrypoint-shell-strict-mode.md` — every shell script must use `set -Eeuo pipefail`
- `03-no-secret-logging.md` — never log JWT, installation token, registration token, remove token
- `04-docker-socket-never-in-runner.md` — runner services must reach Docker through socket-proxy, never the raw host socket
- `05-yaml-anchor-no-env-merge.md` — YAML merge does not deep-merge `environment:` blocks
- `06-base-image-must-be-digest-pinned.md` — every `FROM` line must include a digest
- `07-cleanup-trap-isolation.md` — cleanup handlers must isolate failures via subshells
- `08-no-config-vars-leak-to-jobs.md` — runner config vars must not be readable from workflow jobs
- `09-arithmetic-precedence-bash.md` — bash arithmetic `&` is lower precedence than `==`; over-parenthesize
- `10-no-cd-in-entrypoint.md` — entrypoint must not `cd` away from `/home/runner` (cleanup depends on PWD)

Rules are advisory but reflect lessons learned. New rules go in this index when added.
