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
- `11-socket-proxy-env-minimum.md` — socket-proxy must expose only IMAGES/BUILD/POST/INFO/PING; CONTAINERS et al. are forbidden by default
- `12-runner-cap-add-minimal.md` — runner services must drop ALL caps and re-add only CHOWN/DAC_OVERRIDE/FOWNER/SETGID/SETUID/KILL
- `13-dockerfile-no-broad-copy.md` — `Dockerfile` must not `COPY . .` / `ADD .` — sources must be explicit paths
- `14-use-context-mode-by-default.md` — default to context-mode (`ctx_execute`/`ctx_execute_file`/`ctx_fetch_and_index`) for anything that might fill the context window, not just known-large outputs

Rules are advisory but reflect lessons learned. New rules go in this index when added.
