# Rule: runner configuration vars must not leak into workflow job environments

After `config.sh` registers the runner, `entrypoint.sh` unsets every
variable that is no longer required, so they are not inherited by the
workflow job processes that `run.sh` later spawns.

The current unset list (in `main()`):

```bash
unset RUNNER_DEFAULT_LABELS RUNNER_EXTRA_LABELS RUNNER_LABELS RUNNER_GROUP
unset RUNNER_INSTANCE_NAME RUNNER_WORKDIR GITHUB_WEB_URL
```

Variables that are **intentionally kept** because they are needed by
`cleanup()` / `deregister_runner()` when the runner exits:

| Var | Purpose |
| --- | --- |
| `GITHUB_API_URL` | Endpoint for the remove-token API call |
| `RUNNER_SCOPE` | Picks the org vs repo URL shape |
| `GITHUB_ORG` | Org-scoped remove URL path |
| `GITHUB_REPO_OWNER`, `GITHUB_REPO_NAME` | Repo-scoped remove URL path |
| `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID` | Fallback JWT minting if the pre-computed remove token is empty |
| `GITHUB_APP_PRIVATE_KEY_FILE` | Fallback PEM read for the same purpose |

`RUNNER_REMOVE_TOKEN` is a **shell variable, not exported**, so it lives in
`bash` memory only and is not visible to `run.sh` or job subprocesses.

## Why this matters

GitHub Actions exposes the entire workflow runner environment to job code
via `printenv`. Variables exported by `entrypoint.sh` are inherited by every
job step unless explicitly unset before `exec run.sh`. Cards like
`GITHUB_APP_ID` are not secrets, but `RUNNER_GROUP`, `RUNNER_LABELS`, and
internal config flags are not interesting to workflows and contribute to
fingerprinting / debugging leakage.

## What to do when adding a new RUNNER_* env var

1. Decide if the variable is **read by `entrypoint.sh` before
   registration** (most are) or **needed after registration**.
2. If it is registration-only, add it to the `unset` list in `main()` under
   the `if [[ "${UNSET_CONFIG_VARS:-true}" == "true" ]]; then` block.
3. If it must survive into job environments, document why in a comment.

## Verification

After `docker compose up`, exec into a runner with a workflow active and
run `printenv | sort`. None of the names in the `unset` list should appear.

```bash
docker compose exec runner-1 printenv | grep -E '^(RUNNER_DEFAULT_LABELS|RUNNER_EXTRA_LABELS|RUNNER_LABELS|RUNNER_GROUP|RUNNER_INSTANCE_NAME|RUNNER_WORKDIR|GITHUB_WEB_URL)='
```

Must produce no output during job execution.
